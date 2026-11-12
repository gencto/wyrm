import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/session.dart';
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

  @override
  Future<void> set(String key, Value value) async {
    calls.add(Call('set', key, value: value));
    if (errors[key] case final e?) {
      throw e;
    }
  }

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) async* {
    calls.add(Call('invoke', key, action: action, args: args));
    final id = '$key ▸ $action';
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
    await _delay(key);
    if (errors[key] case final e?) {
      throw e;
    }
    return children_[key] ?? (throw _missing(key));
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

/// A session over a [FakeWyrmApi].
class FakeSession implements WyrmSession {
  FakeSession({
    FakeWyrmApi? api,
    this.who = const WhoAmI(
      subject: 'user:admin',
      site: 'central',
      roles: ['admin'],
      max: 'config',
    ),
  }) : api = api ?? FakeWyrmApi();

  @override
  final FakeWyrmApi api;

  final WhoAmI who;
  // ignore: close_sinks, a test's session lives as long as the test.
  final connected = StreamController<bool>.broadcast();
  var closed = false;

  @override
  Stream<bool> get connection => connected.stream;

  @override
  Uri get base => Uri.parse('http://127.0.0.1:8445');

  @override
  Future<WhoAmI> me() async => who;

  /// The users `/api/users` answers, by name.
  final userTable = <String, GatewayUser>{};

  @override
  Future<List<GatewayUser>> users() async => userTable.values.toList();

  @override
  Future<void> addUser(
    String name,
    String password,
    List<String> roles,
  ) async => userTable[name] = GatewayUser(name, roles);

  @override
  Future<void> removeUser(String name) async => userTable.remove(name);

  @override
  Future<void> setUserRoles(String name, List<String> roles) async =>
      userTable[name] = GatewayUser(name, roles);

  @override
  Future<void> setUserPassword(String name, String password) async {}

  @override
  Future<void> setUserDisabled(String name, {required bool disabled}) async =>
      userTable[name] = GatewayUser(
        name,
        userTable[name]?.roles ?? const [],
        disabled: disabled,
      );

  @override
  Future<void> close() async => closed = true;
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

  @override
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
  }) async {
    this.gateways = gateways;
    this.user = user;
    this.password = password;
    if (error case final Exception e) {
      throw e;
    }
    return session;
  }

  @override
  Future<GatewayProbe> probe(
    Uri gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    probed.add(gateway);
    return answer;
  }
}

/// A store with real [AppDependencies] over in-memory storage and [login].
Store<AppState> fakeStore({AppState? initial, FakeLogin? login}) =>
    Store<AppState>(
      initialState: initial ?? AppState.initial(),
      dependencies: (s) => AppDependencies(
        s,
        InMemoryKeyValueStorage(),
        login: login ?? FakeLogin(),
      ),
    );

/// The store's dependencies, typed.
AppDependencies depsOf(Store<AppState> store) =>
    store.dependencies! as AppDependencies;
