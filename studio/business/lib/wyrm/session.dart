import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrm_client/wyrm_client.dart';

/// Who the gateway says the user is (`GET /api/me`).
final class WhoAmI {
  const WhoAmI({
    required this.subject,
    required this.site,
    required this.roles,
    required this.max,
    this.grants = const [],
  });

  /// Reads the answer of `/api/me`: `{sub, roles, grants, max, exp, site}`.
  factory WhoAmI.fromValue(Value v) => WhoAmI(
    subject: _str(v['sub']) ?? '',
    site: _str(v['site']) ?? '',
    roles: switch (v['roles']) {
      VArray(:final v) => [for (final r in v) ?_str(r)],
      _ => const [],
    },
    max: _str(v['max']),
    grants: switch (v['grants']) {
      VArray(:final v) => [
        for (final g in v)
          if ((_str(g['k']), _str(g['p'])) case (final k?, final p?)) (k, p),
      ],
      _ => const [],
    },
  );

  /// `user:<name>` (or `user:<name>@<site>` below an upstream).
  final String subject;

  /// The site this gateway serves.
  final String site;

  /// The gateway roles of the user (`admin`, `operator`, …).
  final List<String> roles;

  /// The highest level any grant gives (`read`, `write`, `config`), if sent.
  final String? max;

  /// `(key pattern, level)` of each grant.
  final List<(String, String)> grants;

  static String? _str(Value? v) => switch (v) {
    VStr(:final v) => v,
    _ => null,
  };
}

/// One logged-in gateway session: the live client and the identity.
///
/// The interface exists so an action can be tested without a gateway: tests
/// hand `AppDependencies` a [WyrmLogin] that returns a fake.
abstract interface class WyrmSession {
  /// Every broker call goes through this (ADR 0037, docs/studio.md §5.3).
  WyrmApi get api;

  /// `true` while the WebSocket is open; `false` while it reconnects.
  Stream<bool> get connection;

  /// The gateway in use.
  Uri get base;

  /// Who the user is on this gateway.
  Future<WhoAmI> me();

  /// The gateway's users (`/api/users`, admin only).
  Future<List<GatewayUser>> users();

  /// Adds a user with [password] and [roles].
  Future<void> addUser(String name, String password, List<String> roles);

  /// Removes a user.
  Future<void> removeUser(String name);

  /// Sets a user's roles.
  Future<void> setUserRoles(String name, List<String> roles);

  /// Sets a user's password.
  Future<void> setUserPassword(String name, String password);

  /// Disables or enables a user.
  Future<void> setUserDisabled(String name, {required bool disabled});

  // ---- ADR 0050: device keys and the step-up ----

  /// Registers a new device key of this user; [sign] signs the register
  /// nonce with the new key. Returns the gateway's device id. Needs a
  /// password check in the last 5 minutes (`password_required`).
  Future<String> registerDevice({
    required String site,
    required String user,
    required String name,
    required String platform,
    required String alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  });

  /// An idle unlock: a device login that keeps this session.
  Future<void> unlock({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  });

  /// A step-up with the device key for the `confirm_required` refusal [e].
  Future<void> confirmWithDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  });

  /// A step-up with the password (also an idle unlock without a key, and a
  /// fresh password check before a registration); a wrong one throws
  /// `bad_password`.
  Future<void> confirmWithPassword(String password);

  /// The devices of this user.
  Future<List<GatewayDevice>> devices();

  /// The devices of [name] (admin).
  Future<List<GatewayDevice>> userDevices(String name);

  /// Turns off, forgets or (an admin, another user's) removes a device.
  Future<void> removeDevice(String id);

  /// Ends every session of the user and signs out every device.
  Future<void> signOutEverywhere();

  /// Close the client and the HTTP connection.
  Future<void> close();
}

/// What a timed `GET <gateway>/api/me` without a session found
/// (docs/design/specs/login.md §6).
final class GatewayProbe {
  const GatewayProbe.answered(int this.ms) : reason = null;

  const GatewayProbe.noAnswer(String this.reason) : ms = null;

  /// How long the gateway took to answer; null when it did not.
  final int? ms;

  /// Why there is no answer: `connection refused`, `timed out`,
  /// `certificate is not trusted`, …
  final String? reason;

  bool get answered => ms != null;
}

/// Opens a [WyrmSession]: the first of the gateways that accepts the login.
abstract interface class WyrmLogin {
  /// A password login. [device] names this computer's device key, so the
  /// gateway notes that it saw the password (`password_due` clears).
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
    String? device,
  });

  /// A device login on [gateway] (ADR 0050 §1.2): a challenge, the bytes
  /// [sign] gives for it (the OS prompt), the session. A refusal throws a
  /// [WyrmException] with its `code`.
  Future<WyrmSession> openWithDevice(
    Uri gateway, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  });

  /// `GET /api/info` of [gateway] without a session, or null when it does
  /// not answer it (no gateway there, or one older than ADR 0050). Never
  /// throws.
  Future<GatewayInfo?> info(Uri gateway, {Duration timeout});

  /// Asks [gateway] for `/api/me` without a session and times the answer. A
  /// 401 means a gateway is there; anything else within [timeout] is no
  /// answer. Never throws.
  Future<GatewayProbe> probe(Uri gateway, {Duration timeout});
}

/// The real login: `WyrmGateway.loginAny` and a reconnecting client.
///
/// Every `HttpClient` it opens comes from [_client], the one place a
/// gateway's trust (a pinned CA, ADR 0050 §2.3) plugs in.
final class GatewayLogin implements WyrmLogin {
  const GatewayLogin();

  HttpClient _client({Duration? timeout}) {
    final c = HttpClient();
    if (timeout != null) {
      c.connectionTimeout = timeout;
    }
    return c;
  }

  @override
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
    String? device,
  }) async {
    final gw = await WyrmGateway.loginAny(
      gateways,
      user: user,
      password: password,
      device: device,
      http: _client(),
    );
    return _session(gw);
  }

  @override
  Future<WyrmSession> openWithDevice(
    Uri gateway, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final http = _client();
    final WyrmGateway gw;
    try {
      gw = await WyrmGateway.loginWithDevice(
        gateway,
        site: site,
        user: user,
        device: device,
        sign: sign,
        http: http,
      );
    } catch (_) {
      http.close(force: true);
      rethrow;
    }
    return _session(gw);
  }

  Future<WyrmSession> _session(WyrmGateway gw) async {
    try {
      final client = await gw.client();
      return _GatewaySession(gw, client);
    } catch (_) {
      gw.dispose();
      rethrow;
    }
  }

  @override
  Future<GatewayInfo?> info(
    Uri gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final http = _client(timeout: timeout);
    try {
      return await WyrmGateway.info(gateway, http: http).timeout(timeout);
    } on Object {
      return null;
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<GatewayProbe> probe(
    Uri gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final http = _client(timeout: timeout);
    final watch = Stopwatch()..start();
    try {
      final req = await http
          .getUrl(gateway.resolve('/api/me'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout - watch.elapsed);
      await res.drain<void>();
      final ms = watch.elapsedMilliseconds;
      // 401: a gateway, asking for a session. 200 cannot happen without one,
      // but it is a gateway too.
      return res.statusCode == HttpStatus.unauthorized ||
              res.statusCode == HttpStatus.ok
          ? GatewayProbe.answered(ms)
          : GatewayProbe.noAnswer('answered HTTP ${res.statusCode}');
    } on TimeoutException {
      return const GatewayProbe.noAnswer('timed out');
    } on HandshakeException {
      return const GatewayProbe.noAnswer('certificate is not trusted');
    } on TlsException {
      return const GatewayProbe.noAnswer('certificate is not trusted');
    } on SocketException catch (e) {
      final refused = e.osError?.errorCode == 61 || e.osError?.errorCode == 111;
      return GatewayProbe.noAnswer(
        refused
            ? 'connection refused after ${_seconds(watch.elapsed)}'
            : e.message.isEmpty
            ? 'no network route'
            : e.message,
      );
    } on Object catch (e) {
      return GatewayProbe.noAnswer('$e');
    } finally {
      http.close(force: true);
    }
  }

  static String _seconds(Duration d) =>
      d.inMilliseconds < 1000 ? '${d.inMilliseconds} ms' : '${d.inSeconds} s';
}

final class _GatewaySession implements WyrmSession {
  _GatewaySession(this._gw, this._client);

  final WyrmGateway _gw;
  final ReconnectingClient _client;

  @override
  WyrmApi get api => _client;

  @override
  Stream<bool> get connection => _client.connection;

  @override
  Uri get base => _gw.base;

  @override
  Future<WhoAmI> me() async => WhoAmI.fromValue(await _gw.me());

  @override
  Future<List<GatewayUser>> users() => _gw.users();

  @override
  Future<void> addUser(String name, String password, List<String> roles) =>
      _gw.addUser(name, password, roles);

  @override
  Future<void> removeUser(String name) => _gw.removeUser(name);

  @override
  Future<void> setUserRoles(String name, List<String> roles) =>
      _gw.setUserRoles(name, roles);

  @override
  Future<void> setUserPassword(String name, String password) =>
      _gw.setUserPassword(name, password);

  @override
  Future<void> setUserDisabled(String name, {required bool disabled}) =>
      _gw.setUserDisabled(name, disabled);

  @override
  Future<String> registerDevice({
    required String site,
    required String user,
    required String name,
    required String platform,
    required String alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _gw.registerDevice(
    site: site,
    user: user,
    name: name,
    platform: platform,
    alg: alg,
    publicKey: publicKey,
    sign: sign,
  );

  @override
  Future<void> unlock({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _gw.unlock(site: site, user: user, device: device, sign: sign);

  @override
  Future<void> confirmWithDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _gw.confirmWithDevice(
    e: e,
    site: site,
    user: user,
    device: device,
    sign: sign,
  );

  @override
  Future<void> confirmWithPassword(String password) =>
      _gw.confirmWithPassword(password);

  @override
  Future<List<GatewayDevice>> devices() => _gw.devices();

  @override
  Future<List<GatewayDevice>> userDevices(String name) => _gw.userDevices(name);

  @override
  Future<void> removeDevice(String id) => _gw.removeDevice(id);

  @override
  Future<void> signOutEverywhere() => _gw.signOutEverywhere();

  @override
  Future<void> close() async {
    await _client.close();
    _gw.dispose();
  }
}

/// Splits the gateway field into URLs: one, or several separated by commas
/// for a site with a standby broker (ADR 0036). A URL without a scheme gets
/// `http://`. Returns an empty list when nothing usable was typed.
List<Uri> parseGateways(String text) => [
  for (final part in text.split(','))
    if (part.trim() case final s when s.isNotEmpty)
      if (Uri.tryParse(s.contains('://') ? s : 'http://$s') case final u?
          when u.host.isNotEmpty && (u.scheme == 'http' || u.scheme == 'https'))
        u,
];
