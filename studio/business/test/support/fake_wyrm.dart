import 'dart:async';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/common/text_clipboard.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:business/wyrm/session.dart';
import 'package:device_key/testing.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A recorded broker call.
final class Call {
  const Call(this.op, this.key, {this.action, this.args, this.value});

  final String op;
  final String key;
  final String? action;
  final Value? args;
  final Value? value;

  @override
  String toString() =>
      'Call($op $key${action == null ? '' : ' ▸ $action'}'
      '${args == null ? '' : ' $args'}${value == null ? '' : ' = $value'})';
}

/// A [WyrmApi] that records every call and answers from what a test put in.
///
/// Answers are keyed by `key` (children, meta) or `key ▸ action` (invoke).
/// A key with no answer fails the call with `not_found`, as a broker would.
class FakeWyrmApi implements WyrmApi {
  final calls = <Call>[];
  final children_ = <String, List<Child>>{};
  final metas = <String, NodeMeta>{};
  final invokes = <String, List<Value>>{};
  final errors = <String, WyrmException>{};

  /// Actions (`key ▸ action`) answered from their arguments: a transfer in
  /// parts answers each part by its offset.
  final answers = <String, List<Value> Function(Value? args)>{};
  final lists = <String, StreamController<ListUpdate>>{};
  final subs = <String, StreamController<ValEvent>>{};
  final histories = <String, List<HistRow>>{};

  /// Actions (`key ▸ action`) answered by a stream the test drives: each
  /// call opens a controller of its own, kept in [opened] in call order.
  final streamed = <String>{};
  final opened = <String, List<StreamController<Value>>>{};

  /// How long a call waits before it answers, by `key` (children, meta) or
  /// `key ▸ action` (invoke): a slow broker.
  final delays = <String, Duration>{};

  Future<void> _delay(String id) async {
    if (delays[id] case final d?) {
      await Future<void>.delayed(d);
    }
  }

  WyrmException _missing(String what) =>
      WyrmException.of(Status.notFound, 'no answer for $what');

  @override
  Stream<ListUpdate> list(String key) {
    calls.add(Call('list', key));
    return (lists[key] ??= StreamController<ListUpdate>.broadcast()).stream;
  }

  /// What a new subscription of a pattern gets first (the broker answers a
  /// subscription with the stored values).
  final initial = <String, List<ValEvent>>{};

  @override
  Stream<ValEvent> subscribe(String pattern) {
    calls.add(Call('subscribe', pattern));
    // ignore: close_sinks, a test's streams live as long as the test.
    late final StreamController<ValEvent> c;
    c = subs[pattern] ??= StreamController<ValEvent>.broadcast(
      onListen: () {
        for (final e in initial[pattern] ?? const <ValEvent>[]) {
          scheduleMicrotask(() => c.add(e));
        }
      },
    );
    return c.stream;
  }

  /// The gateway whose step-up guards [stepUpKeys] (`set` on a key,
  /// `invoke` as `key ▸ action`): refused with `confirm_required` until the
  /// session is confirmed.
  FakeDevices? stepUp;
  final stepUpKeys = <String>{};

  void guard(String id) {
    if (stepUp case final g? when stepUpKeys.contains(id)) {
      g.check(id);
    }
  }

  @override
  Future<void> set(String key, Value value) async {
    calls.add(Call('set', key, value: value));
    guard(key);
    if (errors[key] case final e?) {
      throw e;
    }
  }

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) async* {
    calls.add(Call('invoke', key, action: action, args: args));
    final id = '$key ▸ $action';
    guard(id);
    final gate = _gateOf(id);
    if (invokesInTurn[id] case [final first, ...]) {
      invokesInTurn[id]!.removeAt(0);
      await gate;
      await Future<void>.delayed(first.$1);
      yield* Stream.fromIterable(first.$2);
      return;
    }
    await gate;
    await _delay(id);
    if (errors[id] case final e?) {
      throw e;
    }
    if (streamed.contains(id)) {
      final c = StreamController<Value>();
      (opened[id] ??= []).add(c);
      yield* c.stream;
      return;
    }
    if (answers[id] case final f?) {
      for (final r in f(args)) {
        yield r;
      }
      return;
    }
    final rows = invokes[id];
    if (rows == null) {
      throw _missing(id);
    }
    for (final r in rows) {
      yield r;
    }
  }

  @override
  Future<NodeMeta> meta(String key) async {
    calls.add(Call('meta', key));
    metaInFlight++;
    if (metaInFlight > metaMaxInFlight) {
      metaMaxInFlight = metaInFlight;
    }
    try {
      if (metaDelay > Duration.zero) {
        await Future<void>.delayed(metaDelay);
      }
      if (errors[key] case final e?) {
        throw e;
      }
      return metas[key] ?? (throw _missing(key));
    } finally {
      metaInFlight--;
    }
  }

  /// How long a `meta` answer takes, and how many were open at once.
  Duration metaDelay = Duration.zero;
  var metaInFlight = 0;
  var metaMaxInFlight = 0;

  @override
  Future<List<Child>> children(String key) async {
    calls.add(Call('children', key));
    final gate = _gateOf(key);
    if (childrenInTurn[key] case [final first, ...]) {
      childrenInTurn[key]!.removeAt(0);
      await gate;
      return first.list ?? (throw first.refusal!);
    }
    await gate;
    await _delay(key);
    if (errors[key] case final e?) {
      throw e;
    }
    return children_[key] ?? (throw _missing(key));
  }

  /// Answers to the next lists of a key, one per call in call order: each
  /// is the list as it was when the call was sent, or its refusal. When it
  /// comes back is the test's to say ([gates]). Before [children_].
  final childrenInTurn = <String, List<ListAnswer>>{};

  /// Gates of the next calls of a key (a list) or of `key ▸ action` (an
  /// invoke), one per call in call order: the call is answered only once
  /// the test opens its gate ([hold]), so the order answers come in is
  /// exact, with no clock (a gateway that serves every call in a task of
  /// its own may answer a later call first).
  final gates = <String, List<Completer<void>>>{};

  /// Holds the next call of [id] until the gate it returns is completed.
  Completer<void> hold(String id) {
    final gate = Completer<void>();
    (gates[id] ??= []).add(gate);
    return gate;
  }

  /// The gate of the call of [id] that is being made now, taken when the
  /// call is made; nothing to wait for when the test holds none.
  Future<void> _gateOf(String id) => switch (gates[id]) {
    [final first, ...] => (gates[id]!..removeAt(0), first.future).$2,
    _ => Future<void>.value(),
  };

  /// Answers to the next calls of an action, by `key ▸ action`, one per
  /// call in call order: each comes back after its own delay (a gateway
  /// that serves every call in a task of its own, so a later call may be
  /// answered first). Before [invokes].
  final invokesInTurn = <String, List<(Duration, List<Value>)>>{};

  /// Documents by `key suffix` (`wy/…/tasks/t1 ~state`).
  final docs = <String, Value>{};

  /// Answers to the next reads of a document, by `key suffix`, one per
  /// call in call order: each is the document as it was when the read was
  /// sent and comes back after its own delay (a gateway that serves every
  /// read in a task of its own). Before [docs].
  final docsInTurn = <String, List<(Duration, Value)>>{};

  @override
  Future<Value> doc(String key, String suffix) async {
    calls.add(Call('doc', key, action: suffix));
    final id = '$key $suffix';
    if (docsInTurn[id] case [final first, ...]) {
      docsInTurn[id]!.removeAt(0);
      await Future<void>.delayed(first.$1);
      return first.$2;
    }
    await _delay(id);
    if (errors[id] case final e?) {
      throw e;
    }
    return docs[id] ?? (throw _missing(id));
  }

  @override
  Future<List<HistRow>> history(
    String key, {
    required String from,
    String to = '',
    String? agg,
    String? window,
    int? limit,
  }) async {
    calls.add(
      Call(
        'history',
        key,
        args: VMap({
          'from': VStr(from),
          'to': VStr(to),
          if (agg != null) 'agg': VStr(agg),
          if (window != null) 'window': VStr(window),
          if (limit != null) 'limit': VInt(limit),
        }),
      ),
    );
    if (errors['$key ▸ history'] case final e?) {
      throw e;
    }
    // `<key> ▸ <agg>` answers a rollup of its own (min, max), and
    // `<key> ▸ <window>` a window of its own (`1m`).
    return histories['$key ▸ $agg'] ??
        histories['$key ▸ $window'] ??
        histories[key] ??
        const [];
  }

  var closed = false;

  @override
  Future<void> close() async => closed = true;
}

/// `/api/me` of a test, its levels written by name as the gateway sends
/// them; a name that is not a level fails the test at once. With no
/// [grants] given, one grant on `wy/**` at [max]: what a gateway sends for
/// a role with that level everywhere (its `max` is the highest level of
/// its grants, so a `max` with no grant is no answer a gateway gives).
GatewayIdentity identityOf({
  required String subject,
  required String site,
  required List<String> roles,
  required String max,
  List<(String, String)>? grants,
}) => GatewayIdentity(
  sub: subject,
  site: site,
  roles: roles,
  max: Perm.fromName(max)!,
  exp: 0,
  grants: [
    for (final (k, p) in grants ?? [('wy/**', max)])
      Grant(k, Perm.fromName(p)!),
  ],
);

/// A session over a [FakeWyrmApi].
class FakeSession implements WyrmSession {
  FakeSession({
    FakeWyrmApi? api,
    GatewayIdentity? who,
    FakeDevices? devices,
    this.me,
  }) : api = api ?? FakeWyrmApi(),
       who =
           who ??
           identityOf(
             subject: 'user:admin',
             site: 'central',
             roles: const ['admin'],
             max: 'config',
           ),
       gateway = devices ?? FakeDevices();

  @override
  final FakeWyrmApi api;

  /// The device side of the gateway.
  final FakeDevices gateway;

  /// The user of this session (`who.subject` without `user:`).
  String get userName => who.sub.replaceFirst('user:', '');

  final GatewayIdentity who;

  /// `/api/me` as it comes over the wire, when a test gives it: decoded as
  /// the real session does (`GatewayIdentity.fromValue`); else [who].
  final Value? me;
  // ignore: close_sinks, a test's session lives as long as the test.
  final connected = StreamController<bool>.broadcast();
  var closed = false;

  @override
  Stream<bool> get connection => connected.stream;

  @override
  Uri get base => Uri.parse('http://127.0.0.1:8445');

  @override
  Future<GatewayIdentity> identity() async => switch (me) {
    final v? => GatewayIdentity.fromValue(v),
    null => who,
  };

  /// The users `/api/users` answers, by name.
  final userTable = <String, GatewayUser>{};

  /// The password each user was given last, as it was sent.
  final passwords = <String, String>{};

  @override
  Future<List<GatewayUser>> users() async => userTable.values.toList();

  @override
  Future<void> addUser(
    String name,
    String password,
    List<String> roles,
  ) async {
    api.calls.add(Call('add_user', name));
    api.guard('user:$name');
    userTable[name] = GatewayUser(name, roles);
    passwords[name] = password;
  }

  @override
  Future<void> removeUser(String name) async => userTable.remove(name);

  @override
  Future<void> setUserRoles(String name, List<String> roles) async =>
      userTable[name] = GatewayUser(name, roles);

  @override
  Future<void> setUserPassword(String name, String password) async =>
      passwords[name] = password;

  @override
  Future<void> setUserDisabled(String name, {required bool disabled}) async =>
      userTable[name] = GatewayUser(
        name,
        userTable[name]?.roles ?? const [],
        disabled: disabled,
      );

  @override
  Future<String> addDevice({
    required String site,
    required String user,
    required String name,
    required DevicePlatform platform,
    required DeviceAlg alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => gateway.register(
    site: site,
    user: user,
    name: name,
    platform: platform,
    publicKey: publicKey,
    sign: sign,
  );

  @override
  Future<void> unlock({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => gateway.login(site: site, user: user, device: device, sign: sign);

  @override
  Future<void> confirmWithDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => gateway.confirmDevice(
    e: e,
    site: site,
    user: user,
    device: device,
    sign: sign,
  );

  @override
  Future<void> confirmWithPassword(String password) =>
      gateway.confirmPassword(password);

  @override
  Future<List<GatewayDevice>> devices() async =>
      gateway.listOf(userName, own: gateway.sessionDevice);

  @override
  Future<List<GatewayDevice>> userDevices(String name) async =>
      gateway.listOf(name);

  @override
  Future<void> removeDevice(String id) async => gateway.remove(id, userName);

  @override
  Future<void> signOutEverywhere() async {
    gateway.signedOutEverywhere++;
    for (final d in gateway.records.values) {
      if (d.user == userName) {
        d.state = 'signed_out';
      }
    }
  }

  @override
  Future<void> close() async => closed = true;
}

/// One device record of [FakeDevices].
final class FakeDeviceRecord {
  FakeDeviceRecord(this.id, this.user, this.name, this.publicKey);

  final String id;
  final String user;
  final String name;
  final Uint8List publicKey;
  var state = 'active';
  String? removedBy;
  var lastUsed = 0;
}

/// The device side of a gateway (ADR 0050): records, nonces, the checks of
/// every signature with [FakeDeviceKey.verify] over the bytes
/// `wyrm_client` builds, the refusal codes and the step-up.
class FakeDevices {
  FakeDevices({
    this.site = 'central',
    this.origin = 'http://127.0.0.1:8445',
    this.password = 'wyrm-demo-1',
  });

  final String site;
  final String origin;
  final String password;

  final records = <String, FakeDeviceRecord>{};
  var _next = 0;
  var _nonce = 0;

  /// The refusal code every device login gets, until a test clears it.
  String? refuse;

  /// `devices_off` for every device call.
  var off = false;

  /// The session was confirmed (a login, a device or a password confirm).
  var confirmed = false;

  /// A registration needs a fresh password check (`password_required`).
  var passwordFresh = true;

  /// The device of the session a device login made.
  String? sessionDevice;

  var logins = 0;
  var confirms = 0;
  var signedOutEverywhere = 0;

  /// What the last `password_due` clear named (a password login's device).
  String? passwordSeen;

  Uint8List _newNonce() =>
      Uint8List.fromList([for (var i = 0; i < 8; i++) (_nonce * 7 + i) & 0xff])
        ..[0] = ++_nonce;

  static WyrmException _code(String code) => WyrmException.of(
    Status.permissionDenied,
    code.replaceAll('_', ' '),
    code: code,
  );

  static WyrmException get _bare =>
      WyrmException.of(Status.permissionDenied, 'unauthorized');

  Future<String> register({
    required String site,
    required String user,
    required String name,
    required DevicePlatform platform,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    if (off) {
      throw _code('devices_off');
    }
    if (!passwordFresh) {
      throw _code('password_required');
    }
    final nonce = _newNonce();
    final sig = await sign(
      deviceRegisterMessage(this.site, origin, user, nonce, publicKey),
    );
    if (!FakeDeviceKey.verify(
      publicKey,
      deviceRegisterMessage(site, origin, user, nonce, publicKey),
      sig,
    )) {
      throw _bare;
    }
    final id = 'd${++_next}';
    records[id] = FakeDeviceRecord(id, user, name, publicKey);
    return id;
  }

  /// A device login (also the idle unlock).
  Future<void> login({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final nonce = _newNonce();
    final sig = await sign(
      deviceLoginMessage(site, origin, user, device, nonce),
    );
    final d = records[device];
    if (d == null ||
        d.user != user ||
        !FakeDeviceKey.verify(
          d.publicKey,
          deviceLoginMessage(this.site, origin, user, device, nonce),
          sig,
        )) {
      throw _bare;
    }
    if (off) {
      throw _code('devices_off');
    }
    if (d.state == 'removed') {
      throw _code('device_removed');
    }
    if (d.state == 'signed_out') {
      throw _code('password_changed');
    }
    if (refuse case final code?) {
      throw _code(code);
    }
    logins++;
    d.lastUsed++;
    sessionDevice = device;
    confirmed = true;
  }

  /// The refusal the step-up guard gives for [id] before a confirm.
  void check(String id) {
    if (!confirmed) {
      throw WyrmException.of(
        Status.permissionDenied,
        'confirm this change',
        code: 'confirm_required',
        nonce: _newNonce(),
        request: Uint8List.fromList(List.filled(32, id.length & 0xff)),
      );
    }
  }

  Future<void> confirmDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final nonce = e.nonce!;
    final request = e.request!;
    final sig = await sign(
      deviceConfirmMessage(site, origin, user, device, nonce, request),
    );
    final d = records[device];
    if (d == null ||
        !FakeDeviceKey.verify(
          d.publicKey,
          deviceConfirmMessage(this.site, origin, user, device, nonce, request),
          sig,
        )) {
      throw _bare;
    }
    confirms++;
    confirmed = true;
  }

  Future<void> confirmPassword(String password) async {
    if (password != this.password) {
      throw _code('bad_password');
    }
    confirms++;
    confirmed = true;
    passwordFresh = true;
  }

  List<GatewayDevice> listOf(String user, {String? own}) => [
    for (final d in records.values)
      if (d.user == user)
        GatewayDevice(
          id: d.id,
          name: d.name,
          platform: DevicePlatform.macos,
          lastUsed: d.lastUsed,
          state: GatewayDeviceState.fromWire(d.state)!,
          thisSession: d.id == own,
          removedBy: d.removedBy,
        ),
  ];

  /// The owner forgets; anyone else (an admin) leaves a tombstone.
  void remove(String id, String by) {
    final d = records[id];
    if (d == null) {
      throw WyrmException.of(Status.notFound, 'no device $id');
    }
    if (d.user == by || d.state == 'removed') {
      records.remove(id);
    } else {
      d
        ..state = 'removed'
        ..removedBy = 'user:$by';
    }
  }
}

/// What one call of a list answers: the list, or its refusal.
final class ListAnswer {
  const ListAnswer(List<Child> this.list) : refusal = null;

  const ListAnswer.refused(WyrmException this.refusal) : list = null;

  final List<Child>? list;
  final WyrmException? refusal;
}

/// Opens [session], or throws [error]; records what it was asked.
class FakeLogin implements WyrmLogin {
  FakeLogin({
    FakeSession? session,
    this.error,
    this.answer = const GatewayProbe.answered(12),
  }) : session = session ?? FakeSession();

  final FakeSession session;
  final Object? error;

  /// What every [probe] finds.
  final GatewayProbe answer;

  /// The gateways [probe] was asked about, in order.
  final probed = <Uri>[];
  List<Uri>? gateways;
  String? user;
  String? password;

  /// The device the last password login named.
  String? device;

  /// What `/api/info` answers; null is a gateway that does not.
  GatewayInfo? info_ = const GatewayInfo(
    site: 'central',
    version: '0.1.0',
    tls: false,
    devices: DevicePolicy(enabled: true),
  );

  @override
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
    String? device,
  }) async {
    this.gateways = gateways;
    this.user = user;
    this.password = password;
    this.device = device;
    if (error case final Exception e) {
      throw e;
    }
    session.gateway
      ..confirmed = true
      ..passwordFresh = true
      ..passwordSeen = device;
    return session;
  }

  @override
  Future<WyrmSession> openWithDevice(
    Uri gateway, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    gateways = [gateway];
    this.user = user;
    await session.gateway.login(
      site: site,
      user: user,
      device: device,
      sign: sign,
    );
    session.gateway.passwordFresh = false;
    return session;
  }

  @override
  Future<GatewayInfo?> info(
    Uri gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async => info_;

  @override
  Future<GatewayProbe> probe(
    Uri gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    probed.add(gateway);
    return answer;
  }
}

/// A store with real [AppDependencies] over in-memory storage (or
/// [settings]), [login] and [keys] (a fake device key that offers nothing
/// unless a test gives one).
Store<AppState> fakeStore({
  AppState? initial,
  FakeLogin? login,
  FakeDeviceKey? keys,
  BaseKeyValueStorage? settings,
  TextClipboard? clipboard,
}) => Store<AppState>(
  initialState: initial ?? AppState.initial(),
  dependencies: (s) => AppDependencies(
    s,
    settings ?? InMemoryKeyValueStorage(),
    login: login ?? FakeLogin(),
    deviceKey: keys ?? FakeDeviceKey(availability: DeviceKeyAvailability.none),
    prompts: const PlainPrompts(),
    // The platform's, unless a test hands in its own: a widget test
    // answers the platform channel itself.
    clipboard: clipboard ?? const SystemClipboard(),
  ),
);

/// A clipboard in memory: what Studio wrote, or what a test put there;
/// [none] is a platform without one.
class FakeClipboard implements TextClipboard {
  FakeClipboard({this.text, this.none = false});

  String? text;
  final bool none;

  /// How long the next writes take, one per write in order (a platform
  /// that answers a later write first when it is quicker).
  final writeDelays = <Duration>[];

  /// How long the next reads take, one per read in order.
  final readDelays = <Duration>[];

  @override
  Future<String?> read() async {
    if (readDelays.isNotEmpty) {
      await Future<void>.delayed(readDelays.removeAt(0));
    }
    return none ? null : text;
  }

  @override
  Future<void> write(String text) async {
    if (writeDelays.isNotEmpty) {
      await Future<void>.delayed(writeDelays.removeAt(0));
    }
    if (!none) {
      this.text = text;
    }
  }
}

/// The store's dependencies, typed.
AppDependencies depsOf(Store<AppState> store) =>
    store.dependencies! as AppDependencies;
