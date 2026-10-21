// The user gateway (crates/wyrm-gateway): CBOR over HTTP for the login,
// a single-use ticket, then a WebSocket with binary CBOR frames.
//
//   POST /api/login {user, password}   → {session, exp}
//   POST /api/ws-ticket (Bearer)       → {ticket, exp}   (single use, 30 s)
//   GET  /api/ws?ticket=…              → WebSocket

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';
import 'frames.dart';

/// A logged-in gateway session. [connect] opens a WebSocket with a fresh
/// ticket each time (also for a reconnect).
class WyrmGateway {
  /// `http://host:port` or `https://host:port`.
  final Uri base;
  final String _session;

  /// Session expiry, seconds since the Unix epoch.
  final int expires;
  final HttpClient _http;

  WyrmGateway._(this.base, this._session, this.expires, this._http);

  /// Log in with [user] and [password]. Pass [http] for a custom
  /// `SecurityContext` (a private CA for the gateway certificate).
  static Future<WyrmGateway> login(Uri base,
      {required String user, required String password, HttpClient? http}) async {
    final client = http ?? HttpClient();
    final r = await _post(client, base.resolve('/api/login'),
        body: {'user': VStr(user), 'password': VStr(password)});
    final session = switch (r['session']) { VStr(:final v) => v, _ => throw _bad('session') };
    final exp = switch (r['exp']) { VInt(:final v) => v, _ => 0 };
    return WyrmGateway._(base, session, exp, client);
  }

  /// `GET /api/me`: `{sub, roles, grants, max, exp, site}`.
  Future<Value> me() => _get(_http, base.resolve('/api/me'), bearer: _session);

  /// Open a WebSocket and return the client over it.
  Future<FrameClient> connect() async {
    final t = await _post(_http, base.resolve('/api/ws-ticket'), bearer: _session);
    final ticket = switch (t['ticket']) { VStr(:final v) => v, _ => throw _bad('ticket') };
    final ws = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
      queryParameters: {'ticket': ticket},
    );
    final sock = await WebSocket.connect(ws.toString(), customClient: _http);
    return FrameClient(WebSocketTransport(sock));
  }

  /// Close the HTTP client (open sockets stay until their clients close).
  void dispose() => _http.close();

  static Future<Value> _post(HttpClient c, Uri url, {Map<String, Value>? body, String? bearer}) async {
    final req = await c.postUrl(url);
    req.headers.contentType = ContentType('application', 'cbor');
    if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    final bytes = body == null ? Uint8List(0) : VMap(body).toCbor();
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
      final status = switch (v['status']) { VInt(:final v) => v, _ => Status.internalError.code };
      final msg = switch (v['message']) { VStr(:final v) => v, _ => 'HTTP ${resp.statusCode}' };
      throw WyrmException(StatusCode(status), msg);
    }
    return v;
  }

  static WyrmException _bad(String what) =>
      WyrmException.of(Status.invalidMessage, 'malformed gateway reply: $what');
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
