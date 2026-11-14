// The user gateway (crates/wyrm-gateway): CBOR over HTTP for the login,
// a single-use ticket, then a WebSocket with binary CBOR frames.
//
//   POST /api/login {user, password}   → {session, exp}
//   POST /api/ws-ticket (Bearer)       → {ticket, exp}   (single use, 30 s)
//   GET  /api/ws?ticket=…              → WebSocket
//   POST /api/invoke?key=…&action=… (Bearer), body = args → {result}
//        (an action with a file parameter whose args do not fit a
//        WebSocket frame, ADR 0011)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';
import 'frames.dart';
import 'reconnect.dart';

/// A logged-in gateway session. [connect] opens a WebSocket with a fresh
/// ticket each time (also for a reconnect).
///
/// A site with a standby broker (ADR 0036) has one gateway per broker:
/// [loginAny] takes them all, in the order to try, and keeps the
/// credentials, so [connect] logs in again on another gateway when the one
/// in use is gone or does not know this session.
class WyrmGateway {
  /// The gateways in the order to try; [base] is the one in use.
  final List<Uri> bases;
  int _current;
  String _session;
  int _expires;
  final HttpClient _http;
  final String? _user;
  final String? _password;

  WyrmGateway._(
    this.bases,
    this._current,
    this._session,
    this._expires,
    this._http,
    this._user,
    this._password,
  );

  /// `http://host:port` or `https://host:port` of the gateway in use.
  Uri get base => bases[_current];

  /// Session expiry, seconds since the Unix epoch.
  int get expires => _expires;

  /// Log in with [user] and [password]. Pass [http] for a custom
  /// `SecurityContext` (a private CA for the gateway certificate).
  static Future<WyrmGateway> login(
    Uri base, {
    required String user,
    required String password,
    String? device,
    HttpClient? http,
  }) async {
    final client = http ?? HttpClient();
    final (session, exp) = await _login(
      client,
      base,
      user,
      password,
      device: device,
    );
    return WyrmGateway._([base], 0, session, exp, client, null, null);
  }

  /// Log in on the first of [bases] that answers; the credentials are kept
  /// for a later login on another of them. A refused password ends the
  /// search at once; any other failure moves on to the next gateway, and
  /// the last one's error is thrown when none answered.
  static Future<WyrmGateway> loginAny(
    List<Uri> bases, {
    required String user,
    required String password,
    HttpClient? http,
  }) async {
    if (bases.isEmpty) throw ArgumentError.value(bases, 'bases', 'no gateway');
    final client = http ?? HttpClient();
    Object last = StateError('no gateway');
    for (var i = 0; i < bases.length; i++) {
      try {
        final (session, exp) = await _login(client, bases[i], user, password);
        return WyrmGateway._(
          List.unmodifiable(bases),
          i,
          session,
          exp,
          client,
          user,
          password,
        );
      } on WyrmException catch (e) {
        if (e.status == StatusCode.of(Status.permissionDenied)) rethrow;
        last = e;
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  static Future<(String, int)> _login(
    HttpClient c,
    Uri base,
    String user,
    String password, {
    String? device,
  }) async {
    final r = await _post(
      c,
      base.resolve('/api/login'),
      body: {
        'user': VStr(user),
        'password': VStr(password),
        'device': ?(device == null ? null : VStr(device)),
      },
    );
    final session = switch (r['session']) {
      VStr(:final v) => v,
      _ => throw _bad('session'),
    };
    final exp = switch (r['exp']) {
      VInt(:final v) => v,
      _ => 0,
    };
    return (session, exp);
  }

  /// Log in again on `bases[at]` with the kept credentials and use it.
  Future<void> _moveTo(int at) async {
    final (user, password) = (_user, _password);
    if (user == null || password == null) {
      throw WyrmException.of(
        Status.permissionDenied,
        'session unknown; log in again',
      );
    }
    final (session, exp) = await _login(_http, bases[at], user, password);
    _session = session;
    _expires = exp;
    _current = at;
  }

  /// `GET /api/me`: `{sub, roles, grants, max, exp, site}`.
  Future<Value> me() => _get(_http, base.resolve('/api/me'), bearer: _session);

  /// Open a WebSocket and return the client over it: on the gateway in
  /// use, or, when that one is gone or does not know this session, on the
  /// next one of [bases] after a new login there. Throws
  /// `permission_denied` only when the credentials themselves are refused
  /// (or, without kept credentials, when the session is gone).
  Future<FrameClient> connect() async {
    Object last = StateError('no gateway');
    for (var i = 0; i < bases.length; i++) {
      final at = (_current + i) % bases.length;
      try {
        if (at != _current) await _moveTo(at);
        return await _connectOn(bases[at]);
      } on WyrmException catch (e) {
        if (e.status != StatusCode.of(Status.permissionDenied)) {
          last = e;
          continue;
        }
        // this gateway does not know the session: once more after a new login
        if (_password == null) rethrow;
        try {
          await _moveTo(at);
          return await _connectOn(bases[at]);
        } on WyrmException catch (again) {
          if (again.status == StatusCode.of(Status.permissionDenied)) rethrow;
          last = again;
        } catch (again) {
          last = again;
        }
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  Future<FrameClient> _connectOn(Uri base) async {
    final t = await _post(
      _http,
      base.resolve('/api/ws-ticket'),
      bearer: _session,
    );
    final ticket = switch (t['ticket']) {
      VStr(:final v) => v,
      _ => throw _bad('ticket'),
    };
    final ws = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
      queryParameters: {'ticket': ticket},
    );
    final sock = await WebSocket.connect(ws.toString(), customClient: _http);
    return FrameClient(WebSocketTransport(sock), bulk: invoke);
  }

  /// A client that opens a new WebSocket (with a fresh ticket) whenever
  /// its socket closes: the broker closes them all when it rebuilds its
  /// router on an ACL change (ADR 0006), and a standby broker's gateway
  /// takes over after a failover (ADR 0036, with [loginAny]). Ends when the
  /// login session does.
  Future<ReconnectingClient> client() => ReconnectingClient.open(connect);

  /// `POST /api/invoke`: one invoke of an action with a file parameter
  /// whose arguments are too large for a WebSocket frame; returns its last
  /// result.
  Future<Value> invoke(String key, String action, Value args) async {
    final url = base
        .resolve('/api/invoke')
        .replace(queryParameters: {'key': key, 'action': action});
    final r = await _post(_http, url, bearer: _session, raw: args.toCbor());
    return r['result'] ?? const VNull();
  }

  /// `GET /api/users` (admin): `[{name, roles, disabled}]`.
  Future<List<GatewayUser>> users() async {
    final r = await _get(_http, base.resolve('/api/users'), bearer: _session);
    return [
      if (r case VArray(:final v))
        for (final u in v) GatewayUser.of(u),
    ];
  }

  /// `POST /api/users {name, password, roles}` (admin).
  Future<void> addUser(String name, String password, List<String> roles) =>
      _post(
        _http,
        base.resolve('/api/users'),
        bearer: _session,
        body: {
          'name': VStr(name),
          'password': VStr(password),
          'roles': VArray([for (final r in roles) VStr(r)]),
        },
      );

  /// `DELETE /api/users/<name>` (admin).
  Future<void> removeUser(String name) async {
    final req = await _http.deleteUrl(_userUrl(name));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_session');
    await _read(await req.close());
  }

  /// `POST /api/users/<name>/password {password}` (admin).
  Future<void> setUserPassword(String name, String password) => _post(
    _http,
    _userUrl(name, 'password'),
    bearer: _session,
    body: {'password': VStr(password)},
  );

  /// `POST /api/users/<name>/roles {roles}` (admin).
  Future<void> setUserRoles(String name, List<String> roles) => _post(
    _http,
    _userUrl(name, 'roles'),
    bearer: _session,
    body: {
      'roles': VArray([for (final r in roles) VStr(r)]),
    },
  );

  /// `POST /api/users/<name>/disabled {disabled}` (admin).
  Future<void> setUserDisabled(String name, bool disabled) => _post(
    _http,
    _userUrl(name, 'disabled'),
    bearer: _session,
    body: {'disabled': VBool(disabled)},
  );

  Uri _userUrl(String name, [String? what]) =>
      base.replace(pathSegments: ['api', 'users', name, ?what]);

  // ---- ADR 0050: gateway info, device keys, step-up ----

  /// `GET /api/info` without a session: what a log-in page needs.
  static Future<GatewayInfo> info(Uri base, {HttpClient? http}) async {
    final c = http ?? HttpClient();
    try {
      return GatewayInfo.of(await _get(c, base.resolve('/api/info')));
    } finally {
      if (http == null) c.close();
    }
  }

  /// Log in with a device key: a login challenge for [device], the bytes of
  /// [deviceLoginMessage] signed by [sign] (the OS prompt), then
  /// `POST /api/device/login`. [site] is the gateway's site (`/api/info`).
  /// A refusal throws a [WyrmException] with its [WyrmException.code].
  static Future<WyrmGateway> loginWithDevice(
    Uri base, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
    HttpClient? http,
  }) async {
    final client = http ?? HttpClient();
    final (session, exp) = await _deviceLogin(
      client,
      base,
      site,
      user,
      device,
      sign,
      null,
    );
    return WyrmGateway._([base], 0, session, exp, client, null, null);
  }

  static Future<(String, int)> _deviceLogin(
    HttpClient c,
    Uri base,
    String site,
    String user,
    String device,
    Future<Uint8List> Function(Uint8List) sign,
    String? keep,
  ) async {
    final ch = await _post(
      c,
      base.resolve('/api/device/challenge'),
      body: {'device': VStr(device)},
    );
    final nonce = _bytes(ch, 'nonce');
    final origin = base.origin;
    final sig = await sign(
      deviceLoginMessage(site, origin, user, device, nonce),
    );
    final r = await _post(
      c,
      base.resolve('/api/device/login'),
      body: {
        'device': VStr(device),
        'origin': VStr(origin),
        'nonce': VBytes(nonce),
        'signature': VBytes(sig),
        'session': ?(keep == null ? null : VStr(keep)),
      },
    );
    final session = switch (r['session']) {
      VStr(:final v) => v,
      _ => throw _bad('session'),
    };
    return (
      session,
      switch (r['exp']) {
        VInt(:final v) => v,
        _ => 0,
      },
    );
  }

  /// Unlock after an idle lock: a device login that keeps this session.
  Future<void> unlock({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final (session, exp) = await _deviceLogin(
      _http,
      base,
      site,
      user,
      device,
      sign,
      _session,
    );
    _session = session;
    _expires = exp;
  }

  /// Register a device key of this session's user (`POST /api/devices`):
  /// the new key signs a `register` nonce ([deviceRegisterMessage]) to
  /// prove it. Returns the device id. Needs a password login in the last
  /// 5 minutes.
  Future<String> registerDevice({
    required String site,
    required String user,
    required String name,
    required String platform,
    required String alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final ch = await _post(
      _http,
      base.resolve('/api/device/challenge'),
      bearer: _session,
      body: {'purpose': const VStr('register')},
    );
    final nonce = _bytes(ch, 'nonce');
    final origin = base.origin;
    final sig = await sign(
      deviceRegisterMessage(site, origin, user, nonce, publicKey),
    );
    final r = await _post(
      _http,
      base.resolve('/api/devices'),
      bearer: _session,
      body: {
        'name': VStr(name),
        'platform': VStr(platform),
        'alg': VStr(alg),
        'public_key': VBytes(publicKey),
        'origin': VStr(origin),
        'nonce': VBytes(nonce),
        'signature': VBytes(sig),
      },
    );
    return switch (r['device']) {
      VStr(:final v) => v,
      _ => throw _bad('device'),
    };
  }

  /// A step-up with the device key, for a `confirm_required` refusal [e].
  Future<void> confirmWithDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final nonce = e.nonce;
    final request = e.request;
    if (nonce == null || request == null) {
      throw WyrmException.of(
        Status.permissionDenied,
        'this session cannot confirm',
      );
    }
    final origin = base.origin;
    final sig = await sign(
      deviceConfirmMessage(site, origin, user, device, nonce, request),
    );
    await _post(
      _http,
      base.resolve('/api/device/confirm'),
      bearer: _session,
      body: {
        'device': VStr(device),
        'origin': VStr(origin),
        'nonce': VBytes(nonce),
        'request': VBytes(request),
        'signature': VBytes(sig),
      },
    );
  }

  /// A step-up with the password (`POST /api/confirm`); a wrong one throws
  /// `bad_password`.
  Future<void> confirmWithPassword(String password) => _post(
    _http,
    base.resolve('/api/confirm'),
    bearer: _session,
    body: {'password': VStr(password)},
  );

  /// `GET /api/devices`: the devices of this session's user.
  Future<List<GatewayDevice>> devices() async => _deviceList(
    await _get(_http, base.resolve('/api/devices'), bearer: _session),
  );

  /// `GET /api/users/<name>/devices` (admin).
  Future<List<GatewayDevice>> userDevices(String name) async => _deviceList(
    await _get(_http, _userUrl(name, 'devices'), bearer: _session),
  );

  /// `DELETE /api/devices/<id>`: turn off (own), forget (a tombstone) or
  /// remove (an admin, another user's device).
  Future<void> removeDevice(String id) async {
    final req = await _http.deleteUrl(
      base.replace(pathSegments: ['api', 'devices', id]),
    );
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_session');
    await _read(await req.close());
  }

  /// `POST /api/me/sign-out`: every session of the user ends, every device
  /// is signed out (this one too).
  Future<void> signOutEverywhere() => _post(
    _http,
    base.resolve('/api/me/sign-out'),
    bearer: _session,
    body: const {},
  );

  static List<GatewayDevice> _deviceList(Value v) => [
    if (v case VArray(:final v))
      for (final d in v) GatewayDevice.of(d),
  ];

  static Uint8List _bytes(Value v, String k) => switch (v[k]) {
    VBytes(:final v) => v,
    _ => throw _bad(k),
  };

  /// Close the HTTP client (open sockets stay until their clients close).
  void dispose() => _http.close();

  static Future<Value> _post(
    HttpClient c,
    Uri url, {
    Map<String, Value>? body,
    Uint8List? raw,
    String? bearer,
  }) async {
    final req = await c.postUrl(url);
    req.headers.contentType = ContentType('application', 'cbor');
    if (bearer != null)
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    final bytes = raw ?? (body == null ? Uint8List(0) : VMap(body).toCbor());
    req.contentLength = bytes.length;
    req.add(bytes);
    return _read(await req.close());
  }

  static Future<Value> _get(HttpClient c, Uri url, {String? bearer}) async {
    final req = await c.getUrl(url);
    if (bearer != null)
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    return _read(await req.close());
  }

  static Future<Value> _read(HttpClientResponse resp) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      b.add(chunk);
    }
    final bytes = b.takeBytes();
    Value v;
    try {
      v = bytes.isEmpty ? const VNull() : Value.fromCbor(bytes);
    } on CborError catch (e) {
      throw WyrmException.of(
        Status.invalidMessage,
        'HTTP ${resp.statusCode}: $e',
      );
    }
    if (resp.statusCode != 200) {
      throw WyrmException.fromError(v, fallback: 'HTTP ${resp.statusCode}');
    }
    return v;
  }

  static WyrmException _bad(String what) =>
      WyrmException.of(Status.invalidMessage, 'malformed gateway reply: $what');
}

/// What a device signs to log in (ADR 0050):
/// `["wyrm-device-login/1", site, origin, user, device, nonce]`, canonical CBOR.
Uint8List deviceLoginMessage(
  String site,
  String origin,
  String user,
  String device,
  Uint8List nonce,
) => VArray([
  const VStr('wyrm-device-login/1'),
  VStr(site),
  VStr(origin),
  VStr(user),
  VStr(device),
  VBytes(nonce),
]).toCbor();

/// What a new key signs at registration:
/// `["wyrm-device-register/1", site, origin, user, nonce, public_key]`.
Uint8List deviceRegisterMessage(
  String site,
  String origin,
  String user,
  Uint8List nonce,
  Uint8List publicKey,
) => VArray([
  const VStr('wyrm-device-register/1'),
  VStr(site),
  VStr(origin),
  VStr(user),
  VBytes(nonce),
  VBytes(publicKey),
]).toCbor();

/// What a device signs for a step-up:
/// `["wyrm-device-confirm/1", site, origin, user, device, nonce, request]`.
Uint8List deviceConfirmMessage(
  String site,
  String origin,
  String user,
  String device,
  Uint8List nonce,
  Uint8List request,
) => VArray([
  const VStr('wyrm-device-confirm/1'),
  VStr(site),
  VStr(origin),
  VStr(user),
  VStr(device),
  VBytes(nonce),
  VBytes(request),
]).toCbor();

/// `GET /api/info` (ADR 0050 §2.2).
class GatewayInfo {
  final String site;
  final String version;
  final bool tls;
  final String role;
  final String? pair;
  final List<String> up;
  final String minStudio;

  /// The CA code (32 hex digits) and the CA certificate (DER), over TLS
  /// when the broker knows its CA.
  final String? caFp;
  final Uint8List? ca;

  /// The DNS and IP names of the gateway's certificate.
  final List<String> names;
  final DevicePolicy devices;

  const GatewayInfo({
    required this.site,
    required this.version,
    required this.tls,
    this.role = 'active',
    this.pair,
    this.up = const [],
    this.minStudio = '0',
    this.caFp,
    this.ca,
    this.names = const [],
    this.devices = const DevicePolicy(),
  });

  factory GatewayInfo.of(Value v) => GatewayInfo(
    site: _str(v['site']) ?? '',
    version: _str(v['version']) ?? '',
    tls: v['tls'] == const VBool(true),
    role: _str(v['role']) ?? 'active',
    pair: _str(v['pair']),
    up: _strs(v['up']),
    minStudio: _str(v['min_studio']) ?? '0',
    caFp: _str(v['ca_fp']),
    ca: switch (v['ca']) {
      VBytes(:final v) => v,
      _ => null,
    },
    names: _strs(v['names']),
    devices: DevicePolicy.of(v['devices']),
  );
}

/// `gateway.devices` as `/api/info` tells it.
class DevicePolicy {
  final bool enabled;
  final int maxPerUser;
  final int passwordEveryDays;
  final int idleLockMaxMin;

  /// `none` or `config`.
  final String stepUp;
  final bool allowDeviceCredential;

  const DevicePolicy({
    this.enabled = false,
    this.maxPerUser = 5,
    this.passwordEveryDays = 30,
    this.idleLockMaxMin = 30,
    this.stepUp = 'none',
    this.allowDeviceCredential = false,
  });

  factory DevicePolicy.of(Value? v) => DevicePolicy(
    enabled: v?['enabled'] == const VBool(true),
    maxPerUser: _int(v?['max_per_user']) ?? 5,
    passwordEveryDays: _int(v?['password_every_days']) ?? 30,
    idleLockMaxMin: _int(v?['idle_lock_max_min']) ?? 30,
    stepUp: _str(v?['step_up']) ?? 'none',
    allowDeviceCredential: v?['allow_device_credential'] == const VBool(true),
  );
}

/// A device record (`/api/devices`).
class GatewayDevice {
  final String id;
  final String name;
  final String platform;
  final String alg;
  final int added;
  final int lastUsed;
  final int passwordAt;
  final int passwordDueAt;

  /// `active`, `removed` or `signed_out`.
  final String state;
  final bool thisSession;
  final String? removedBy;

  const GatewayDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.alg = 'es256',
    this.added = 0,
    this.lastUsed = 0,
    this.passwordAt = 0,
    this.passwordDueAt = 0,
    this.state = 'active',
    this.thisSession = false,
    this.removedBy,
  });

  factory GatewayDevice.of(Value v) => GatewayDevice(
    id: _str(v['id']) ?? '',
    name: _str(v['name']) ?? '',
    platform: _str(v['platform']) ?? '',
    alg: _str(v['alg']) ?? 'es256',
    added: _int(v['added']) ?? 0,
    lastUsed: _int(v['last_used']) ?? 0,
    passwordAt: _int(v['password_at']) ?? 0,
    passwordDueAt: _int(v['password_due_at']) ?? 0,
    state: _str(v['state']) ?? 'active',
    thisSession: v['this'] == const VBool(true),
    removedBy: _str(v['removed_by']),
  );
}

String? _str(Value? v) => switch (v) {
  VStr(:final v) => v,
  _ => null,
};

int? _int(Value? v) => switch (v) {
  VInt(:final v) => v,
  _ => null,
};

List<String> _strs(Value? v) => [
  if (v case VArray(:final v))
    for (final s in v)
      if (s case VStr(:final v)) v,
];

/// A user of the gateway (`/api/users`).
class GatewayUser {
  final String name;
  final List<String> roles;
  final bool disabled;

  /// Devices that can log in (ADR 0050).
  final int devices;

  const GatewayUser(
    this.name,
    this.roles, {
    this.disabled = false,
    this.devices = 0,
  });

  factory GatewayUser.of(Value v) => GatewayUser(
    switch (v['name']) {
      VStr(:final v) => v,
      _ => '',
    },
    switch (v['roles']) {
      VArray(:final v) => [
        for (final r in v)
          if (r case VStr(:final v)) v,
      ],
      _ => const [],
    },
    disabled: v['disabled'] == const VBool(true),
    devices: _int(v['devices']) ?? 0,
  );
}

/// [FrameTransport] over a `dart:io` WebSocket (binary CBOR frames).
class WebSocketTransport implements FrameTransport {
  final WebSocket _ws;
  late final Stream<Value> _in;

  WebSocketTransport(this._ws) {
    _in = _ws
        .where((m) => m is List<int>)
        .map((m) => decodeFrame(m as List<int>))
        .handleError((Object _) {}, test: (e) => e is CborError)
        .asBroadcastStream();
  }

  @override
  Stream<Value> get incoming => _in;

  @override
  void send(Map<String, Value> frame) => _ws.add(encodeFrame(frame));

  @override
  Future<void> close() => _ws.close();

  /// Close code from the server (`4001` = session expired or revoked).
  int? get closeCode => _ws.closeCode;
}
