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
    HttpClient? http,
  }) async {
    final client = http ?? HttpClient();
    final (session, exp) = await _login(client, base, user, password);
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
        return WyrmGateway._(List.unmodifiable(bases), i, session, exp, client, user, password);
      } on WyrmException catch (e) {
        if (e.status == StatusCode.of(Status.permissionDenied)) rethrow;
        last = e;
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  static Future<(String, int)> _login(HttpClient c, Uri base, String user, String password) async {
    final r = await _post(
      c,
      base.resolve('/api/login'),
      body: {'user': VStr(user), 'password': VStr(password)},
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
      throw WyrmException.of(Status.permissionDenied, 'session unknown; log in again');
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
    final t = await _post(_http, base.resolve('/api/ws-ticket'), bearer: _session);
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

  Uri _userUrl(String name, [String? what]) => base.replace(
    pathSegments: ['api', 'users', name, ?what],
  );

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
    if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    final bytes = raw ?? (body == null ? Uint8List(0) : VMap(body).toCbor());
    req.contentLength = bytes.length;
    req.add(bytes);
    return _read(await req.close());
  }

  static Future<Value> _get(HttpClient c, Uri url, {String? bearer}) async {
    final req = await c.getUrl(url);
    if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
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
      throw WyrmException.of(Status.invalidMessage, 'HTTP ${resp.statusCode}: $e');
    }
    if (resp.statusCode != 200) {
      final status = switch (v['status']) {
        VInt(:final v) => v,
        _ => Status.internalError.code,
      };
      final msg = switch (v['message']) {
        VStr(:final v) => v,
        _ => 'HTTP ${resp.statusCode}',
      };
      throw WyrmException(StatusCode(status), msg);
    }
    return v;
  }

  static WyrmException _bad(String what) =>
      WyrmException.of(Status.invalidMessage, 'malformed gateway reply: $what');
}

/// A user of the gateway (`/api/users`).
class GatewayUser {
  final String name;
  final List<String> roles;
  final bool disabled;

  const GatewayUser(this.name, this.roles, {this.disabled = false});

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
  );
}

/// [FrameTransport] over a `dart:io` WebSocket (binary CBOR frames).
class WebSocketTransport implements FrameTransport {
  final WebSocket _ws;
  late final Stream<Value> _in;

  WebSocketTransport(this._ws) {
    _in =
        _ws
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
