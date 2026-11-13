// The user gateway from a browser: the same protocol and the same public
// API as `gateway.dart`, over `fetch` and the browser's `WebSocket`
// (`package:web`) instead of `dart:io`. `wyrm_client.dart` exports this
// file where `dart:js_interop` exists and `gateway.dart` everywhere else.
//
// A browser sends these requests only to its own origin unless the gateway
// answers with CORS headers (it sends none), so the page must be served
// from the gateway's origin or through a reverse proxy in front of both.
// There is no custom `HttpClient` here: the browser's certificate store
// decides which gateway certificate is trusted.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';
import 'frames.dart';
import 'reconnect.dart';

/// A logged-in gateway session (see `gateway.dart` for the contract).
class WyrmGateway {
  /// The gateways in the order to try; [base] is the one in use.
  final List<Uri> bases;
  int _current;
  String _session;
  int _expires;
  final String? _user;
  final String? _password;

  WyrmGateway._(
    this.bases,
    this._current,
    this._session,
    this._expires,
    this._user,
    this._password,
  );

  /// `http://host:port` or `https://host:port` of the gateway in use.
  Uri get base => bases[_current];

  /// Session expiry, seconds since the Unix epoch.
  int get expires => _expires;

  /// Log in with [user] and [password].
  static Future<WyrmGateway> login(
    Uri base, {
    required String user,
    required String password,
  }) async {
    final (session, exp) = await _login(base, user, password);
    return WyrmGateway._([base], 0, session, exp, null, null);
  }

  /// Log in on the first of [bases] that answers; the credentials are kept
  /// for a later login on another of them.
  static Future<WyrmGateway> loginAny(
    List<Uri> bases, {
    required String user,
    required String password,
  }) async {
    if (bases.isEmpty) throw ArgumentError.value(bases, 'bases', 'no gateway');
    Object last = StateError('no gateway');
    for (var i = 0; i < bases.length; i++) {
      try {
        final (session, exp) = await _login(bases[i], user, password);
        return WyrmGateway._(List.unmodifiable(bases), i, session, exp, user, password);
      } on WyrmException catch (e) {
        if (e.status == StatusCode.of(Status.permissionDenied)) rethrow;
        last = e;
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  static Future<(String, int)> _login(Uri base, String user, String password) async {
    final r = await _post(
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

  Future<void> _moveTo(int at) async {
    final (user, password) = (_user, _password);
    if (user == null || password == null) {
      throw WyrmException.of(Status.permissionDenied, 'session unknown; log in again');
    }
    final (session, exp) = await _login(bases[at], user, password);
    _session = session;
    _expires = exp;
    _current = at;
  }

  /// `GET /api/me`: `{sub, roles, grants, max, exp, site}`.
  Future<Value> me() => _send('GET', base.resolve('/api/me'), bearer: _session);

  /// Open a WebSocket and return the client over it (on the next gateway
  /// after a new login when this one is gone, as in `gateway.dart`).
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
    final t = await _post(base.resolve('/api/ws-ticket'), bearer: _session);
    final ticket = switch (t['ticket']) {
      VStr(:final v) => v,
      _ => throw _bad('ticket'),
    };
    final ws = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
      queryParameters: {'ticket': ticket},
    );
    return FrameClient(await WebSocketTransport.connect(ws), bulk: invoke);
  }

  /// A client that opens a new WebSocket whenever its socket closes.
  Future<ReconnectingClient> client() => ReconnectingClient.open(connect);

  /// `POST /api/invoke`: one invoke whose arguments are too large for a
  /// WebSocket frame; returns its last result.
  Future<Value> invoke(String key, String action, Value args) async {
    final url = base
        .resolve('/api/invoke')
        .replace(queryParameters: {'key': key, 'action': action});
    final r = await _post(url, bearer: _session, raw: args.toCbor());
    return r['result'] ?? const VNull();
  }

  /// `GET /api/users` (admin): `[{name, roles, disabled}]`.
  Future<List<GatewayUser>> users() async {
    final r = await _send('GET', base.resolve('/api/users'), bearer: _session);
    return [
      if (r case VArray(:final v))
        for (final u in v) GatewayUser.of(u),
    ];
  }

  /// `POST /api/users {name, password, roles}` (admin).
  Future<void> addUser(String name, String password, List<String> roles) => _post(
    base.resolve('/api/users'),
    bearer: _session,
    body: {
      'name': VStr(name),
      'password': VStr(password),
      'roles': VArray([for (final r in roles) VStr(r)]),
    },
  );

  /// `DELETE /api/users/<name>` (admin).
  Future<void> removeUser(String name) => _send('DELETE', _userUrl(name), bearer: _session);

  /// `POST /api/users/<name>/password {password}` (admin).
  Future<void> setUserPassword(String name, String password) =>
      _post(_userUrl(name, 'password'), bearer: _session, body: {'password': VStr(password)});

  /// `POST /api/users/<name>/roles {roles}` (admin).
  Future<void> setUserRoles(String name, List<String> roles) => _post(
    _userUrl(name, 'roles'),
    bearer: _session,
    body: {
      'roles': VArray([for (final r in roles) VStr(r)]),
    },
  );

  /// `POST /api/users/<name>/disabled {disabled}` (admin).
  Future<void> setUserDisabled(String name, bool disabled) =>
      _post(_userUrl(name, 'disabled'), bearer: _session, body: {'disabled': VBool(disabled)});

  Uri _userUrl(String name, [String? what]) => base.replace(
    pathSegments: ['api', 'users', name, ?what],
  );

  /// Nothing to close: `fetch` holds no client.
  void dispose() {}

  static Future<Value> _post(
    Uri url, {
    Map<String, Value>? body,
    Uint8List? raw,
    String? bearer,
  }) => _send(
    'POST',
    url,
    bearer: bearer,
    body: raw ?? (body == null ? Uint8List(0) : VMap(body).toCbor()),
  );

  static Future<Value> _send(String method, Uri url, {Uint8List? body, String? bearer}) async {
    final headers = web.Headers();
    if (body != null) headers.append('content-type', 'application/cbor');
    if (bearer != null) headers.append('authorization', 'Bearer $bearer');
    final web.Response resp;
    try {
      resp =
          await web.window
              .fetch(
                url.toString().toJS,
                web.RequestInit(method: method, headers: headers, body: body?.toJS),
              )
              .toDart;
    } catch (e) {
      // A refused connection and a response blocked by CORS look the same
      // to a page: `TypeError: Failed to fetch`.
      throw WyrmException.of(Status.disconnected, 'no answer from $url: $e');
    }
    final bytes = (await resp.arrayBuffer().toDart).toDart.asUint8List();
    Value v;
    try {
      v = bytes.isEmpty ? const VNull() : Value.fromCbor(bytes);
    } on CborError catch (e) {
      throw WyrmException.of(Status.invalidMessage, 'HTTP ${resp.status}: $e');
    }
    if (resp.status != 200) {
      final status = switch (v['status']) {
        VInt(:final v) => v,
        _ => Status.internalError.code,
      };
      final msg = switch (v['message']) {
        VStr(:final v) => v,
        _ => 'HTTP ${resp.status}',
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

/// [FrameTransport] over the browser's WebSocket (binary CBOR frames).
class WebSocketTransport implements FrameTransport {
  final web.WebSocket _ws;
  final _in = StreamController<Value>.broadcast();
  int? _closeCode;

  WebSocketTransport._(this._ws) {
    _ws.addEventListener(
      'message',
      ((web.MessageEvent e) {
        final data = e.data;
        if (data.isA<JSArrayBuffer>()) {
          try {
            _in.add(decodeFrame((data as JSArrayBuffer).toDart.asUint8List()));
          } on CborError {
            // not a frame: dropped, as on the `dart:io` transport
          }
        }
      }).toJS,
    );
    _ws.addEventListener(
      'close',
      ((web.CloseEvent e) {
        _closeCode = e.code;
        _in.close();
      }).toJS,
    );
  }

  /// Opens [url] (`ws://` or `wss://`); fails with `disconnected` when the
  /// socket closes before it opened.
  static Future<WebSocketTransport> connect(Uri url) {
    final ws = web.WebSocket(url.toString())..binaryType = 'arraybuffer';
    final t = WebSocketTransport._(ws);
    final opened = Completer<WebSocketTransport>();
    ws.addEventListener(
      'open',
      ((web.Event _) {
        if (!opened.isCompleted) opened.complete(t);
      }).toJS,
    );
    void failed(web.Event _) {
      if (!opened.isCompleted) {
        opened.completeError(WyrmException.of(Status.disconnected, 'WebSocket did not open: $url'));
      }
    }

    ws.addEventListener('error', failed.toJS);
    ws.addEventListener('close', failed.toJS);
    return opened.future;
  }

  @override
  Stream<Value> get incoming => _in.stream;

  @override
  void send(Map<String, Value> frame) => _ws.send(encodeFrame(frame).toJS);

  @override
  Future<void> close() async => _ws.close();

  /// Close code from the server (`4001` = session expired or revoked).
  int? get closeCode => _closeCode;
}
