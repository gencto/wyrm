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
import 'gateway_types.dart';
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
  /// the last one's error is thrown when none answered. [device] names the
  /// device key of this computer (ADR 0050): the gateway notes that it saw
  /// the password, so its `password_due` clears.
  static Future<WyrmGateway> loginAny(
    List<Uri> bases, {
    required String user,
    required String password,
    String? device,
    HttpClient? http,
  }) async {
    if (bases.isEmpty) throw ArgumentError.value(bases, 'bases', 'no gateway');
    final client = http ?? HttpClient();
    Object last = StateError('no gateway');
    for (var i = 0; i < bases.length; i++) {
      try {
        final (session, exp) = await _login(
          client,
          bases[i],
          user,
          password,
          device: device,
        );
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
    final s = decodeReply(r, GatewaySession.fromValue);
    return (s.session, s.exp);
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

  /// `GET /api/me`: who this session is.
  Future<GatewayIdentity> identity() async => decodeReply<GatewayIdentity>(
    await _get(_http, base.resolve('/api/me'), bearer: _session),
    GatewayIdentity.fromValue,
  );

  /// `GET /api/me` as a plain value: `{sub, roles, grants, max, exp, site}`.
  @Deprecated('Use identity(): it answers a GatewayIdentity')
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
    final ticket = decodeReply(t, (v) => WireMap.of(v, 'ws-ticket').str('ticket'));
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

  /// `POST /api/invoke`: one invoke of an action with a file parameter (a
  /// file or a part of one) whose arguments are too large for a WebSocket
  /// frame; returns its last result. A refusal arrives as the gateway's
  /// [WyrmException]; a connection cut while the body goes (a session that
  /// ended, a gateway gone) as one with status `disconnected` that says so,
  /// not as a [SocketException].
  Future<Value> invoke(String key, String action, Value args) async {
    final url = base
        .resolve('/api/invoke')
        .replace(queryParameters: {'key': key, 'action': action});
    final body = args.toCbor();
    try {
      final r = await _post(_http, url, bearer: _session, raw: body);
      return r['result'] ?? const VNull();
    } on SocketException catch (e) {
      throw _cutOff(action, body.length, e.message);
    } on HttpException catch (e) {
      throw _cutOff(action, body.length, e.message);
    }
  }

  static WyrmException _cutOff(String action, int size, String why) =>
      WyrmException.of(
        Status.disconnected,
        'the gateway closed the connection while $action sent $size bytes '
        '($why): log in again if the session ended, or try again',
      );

  /// `GET /api/users` (admin): `[{name, roles, disabled}]`.
  Future<List<GatewayUser>> users() async => decodeReply<List<GatewayUser>>(
    await _get(_http, base.resolve('/api/users'), bearer: _session),
    GatewayUser.listFromValue,
  );

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
      return decodeReply<GatewayInfo>(
        await _get(c, base.resolve('/api/info')),
        GatewayInfo.fromValue,
      );
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
    final nonce = _nonce(ch);
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
    final s = decodeReply(r, GatewaySession.fromValue);
    return (s.session, s.exp);
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
  /// 5 minutes (else `password_required`).
  Future<String> addDevice({
    required String site,
    required String user,
    required String name,
    required DevicePlatform platform,
    required DeviceAlg alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _register(site, user, name, platform.wire, alg.wire, publicKey, sign);

  /// [addDevice] with the platform and the algorithm as text: a misspelt
  /// one (`mac`) reaches the gateway, which refuses it.
  @Deprecated('Use addDevice: it takes DevicePlatform and DeviceAlg')
  Future<String> registerDevice({
    required String site,
    required String user,
    required String name,
    required String platform,
    required String alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _register(site, user, name, platform, alg, publicKey, sign);

  Future<String> _register(
    String site,
    String user,
    String name,
    String platform,
    String alg,
    Uint8List publicKey,
    Future<Uint8List> Function(Uint8List message) sign,
  ) async {
    final ch = await _post(
      _http,
      base.resolve('/api/device/challenge'),
      bearer: _session,
      body: {'purpose': const VStr('register')},
    );
    final nonce = _nonce(ch);
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
    return decodeReply(r, (v) => WireMap.of(v, 'POST /api/devices').str('device'));
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

  static List<GatewayDevice> _deviceList(Value v) =>
      decodeReply(v, GatewayDevice.listFromValue);

  /// The nonce of a `/api/device/challenge` answer `{nonce, exp}`.
  static Uint8List _nonce(Value v) =>
      decodeReply(v, (v) => WireMap.of(v, 'challenge').bytes('nonce'));

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
    if (bearer != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    final bytes = raw ?? (body == null ? Uint8List(0) : VMap(body).toCbor());
    req.contentLength = bytes.length;
    req.add(bytes);
    return _read(await req.close());
  }

  static Future<Value> _get(HttpClient c, Uri url, {String? bearer}) async {
    final req = await c.getUrl(url);
    if (bearer != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
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

/// [FrameTransport] over a `dart:io` WebSocket (binary CBOR frames).
class WebSocketTransport implements FrameTransport {
  final WebSocket _ws;
  late final Stream<Value> _in;

  WebSocketTransport(this._ws) {
    _in = _ws
        .expand<Value>(
          (Object? m) => m is List<int> ? [decodeFrame(m)] : const [],
        )
        .handleError((Object _) {}, test: (e) => e is CborError)
        .asBroadcastStream();
  }

  @override
  Stream<Value> get incoming => _in;

  @override
  void send(FrameRequest frame) => _ws.add(encodeFrame(frame));

  @override
  Future<void> close() => _ws.close();

  /// Close code from the server (`4001` = session expired or revoked).
  int? get closeCode => _ws.closeCode;
}
