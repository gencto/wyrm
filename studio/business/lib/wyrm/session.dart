import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:models/answer_fault.dart';
import 'package:models/gateway_field_problem.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'discovery.dart';

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
  GatewayAddress get base;

  /// Who the user is on this gateway (`GET /api/me`).
  Future<GatewayIdentity> identity();

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
  Future<String> addDevice({
    required String site,
    required String user,
    required String name,
    required DevicePlatform platform,
    required DeviceAlg alg,
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

/// A gateway's address: its URL, which never holds `user:password@`. It is
/// made only by [parseGateways], which refuses a URL with credentials, so a
/// gateway that travels as one (the login, the session, the site on
/// screen, an error's object, the log) never has them.
final class GatewayAddress {
  const GatewayAddress._(this.uri);

  /// The URL: scheme, host, port and path, no user info.
  final Uri uri;

  /// `https://plant.local:8445`.
  String get text => uri.toString();

  /// `https://plant.local:8445`, without the path.
  String get origin => uri.origin;

  @override
  bool operator ==(Object other) => other is GatewayAddress && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => text;
}

/// What a timed `GET <gateway>/api/me` without a session found
/// (docs/design/specs/login.md §6).
final class GatewayProbe {
  const GatewayProbe.answered(int this.ms) : why = null;

  const GatewayProbe.noAnswer(AnswerFault this.why) : ms = null;

  /// How long the gateway took to answer; null when it did not.
  final int? ms;

  /// Why there is no answer; the screen says it.
  final AnswerFault? why;

  bool get answered => ms != null;
}

/// Opens a [WyrmSession]: the first of the gateways that accepts the login.
abstract interface class WyrmLogin {
  /// A password login. [device] names this computer's device key, so the
  /// gateway notes that it saw the password (`password_due` clears).
  Future<WyrmSession> open(
    List<GatewayAddress> gateways, {
    required String user,
    required String password,
    String? device,
  });

  /// A device login on [gateway] (ADR 0050 §1.2): a challenge, the bytes
  /// [sign] gives for it (the OS prompt), the session. A refusal throws a
  /// [WyrmException] with its `code`.
  Future<WyrmSession> openWithDevice(
    GatewayAddress gateway, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  });

  /// `GET /api/info` of [gateway] without a session, or null when it does
  /// not answer it (no gateway there, or one older than ADR 0050) or
  /// answers something that is not one (logged with the field). Never
  /// throws.
  Future<GatewayInfo?> info(GatewayAddress gateway, {Duration timeout});

  /// Asks [gateway] for `/api/me` without a session and times the answer. A
  /// 401 means a gateway is there; anything else within [timeout] is no
  /// answer. Never throws.
  Future<GatewayProbe> probe(GatewayAddress gateway, {Duration timeout});
}

/// The real login: `WyrmGateway.loginAny` and a reconnecting client.
///
/// Every connection goes through [trust]: an origin with a pinned CA
/// trusts that CA alone, and its name may stand for an address
/// (ADR 0050 §2.3, decision 10). The probe of login.md §6 uses the same
/// client, so a pinned gateway answers it, and so do the device calls of
/// ADR 0050 §1 (`/api/info`, the device login, and every call of a session
/// made by it: register, unlock, confirm, the device list).
final class GatewayLogin implements WyrmLogin {
  const GatewayLogin({this.trust});

  /// The pins in force when a connection opens; none when null.
  final GatewayTrust Function()? trust;

  HttpClient _client({Duration? timeout}) =>
      (trust?.call() ?? const GatewayTrust()).client(timeout: timeout);

  @override
  Future<WyrmSession> open(
    List<GatewayAddress> gateways, {
    required String user,
    required String password,
    String? device,
  }) async {
    final gw = await WyrmGateway.loginAny(
      [for (final g in gateways) g.uri],
      user: user,
      password: password,
      device: device,
      http: _client(),
    );
    return _session(gw, gateways);
  }

  @override
  Future<WyrmSession> openWithDevice(
    GatewayAddress gateway, {
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) async {
    final http = _client();
    final WyrmGateway gw;
    try {
      gw = await WyrmGateway.loginWithDevice(
        gateway.uri,
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
    return _session(gw, [gateway]);
  }

  /// The session on [gw], whose base is the one of [asked] it opened on.
  Future<WyrmSession> _session(
    WyrmGateway gw,
    List<GatewayAddress> asked,
  ) async {
    try {
      final client = await gw.client();
      final base = asked.where((g) => g.origin == gw.base.origin).firstOrNull;
      return _GatewaySession(gw, client, base ?? asked.first);
    } catch (_) {
      gw.dispose();
      rethrow;
    }
  }

  @override
  Future<GatewayInfo?> info(
    GatewayAddress gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final http = _client(timeout: timeout);
    try {
      return await WyrmGateway.gatewayInfo(
        gateway.uri,
        http: http,
      ).timeout(timeout);
    } on WyrmException catch (e) {
      // A gateway that answers, but not with what ADR 0050 decision 10
      // says: no policy is taken from it, and the log names the field.
      if (e.status == StatusCode.of(Status.invalidMessage)) {
        _log.warning('GET ${gateway.origin}/api/info: ${e.message}');
      }
      return null;
    } on Object {
      return null;
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<GatewayProbe> probe(
    GatewayAddress gateway, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final http = _client(timeout: timeout);
    final watch = Stopwatch()..start();
    try {
      final req = await http
          .getUrl(gateway.uri.resolve('/api/me'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout - watch.elapsed);
      await res.drain<void>();
      final ms = watch.elapsedMilliseconds;
      // 401: a gateway, asking for a session. 200 cannot happen without one,
      // but it is a gateway too.
      return res.statusCode == HttpStatus.unauthorized ||
              res.statusCode == HttpStatus.ok
          ? GatewayProbe.answered(ms)
          : GatewayProbe.noAnswer(AnswerFault.http(res.statusCode));
    } on TimeoutException {
      return const GatewayProbe.noAnswer(AnswerFault.timedOut());
    } on HandshakeException {
      return const GatewayProbe.noAnswer(AnswerFault.untrusted());
    } on TlsException {
      return const GatewayProbe.noAnswer(AnswerFault.untrusted());
    } on SocketException catch (e) {
      final refused = e.osError?.errorCode == 61 || e.osError?.errorCode == 111;
      return GatewayProbe.noAnswer(
        refused
            ? AnswerFault.refusedAfter(watch.elapsedMilliseconds)
            : e.message.isEmpty
            ? const AnswerFault.noRoute()
            : AnswerFault.said(e.message),
      );
    } on HttpException catch (e) {
      // its `toString` holds the whole URL; its message does not
      return GatewayProbe.noAnswer(AnswerFault.said(e.message));
    } on Object catch (e) {
      _log.warning(
        'probe of $gateway: ${e.runtimeType}',
      );
      return GatewayProbe.noAnswer(AnswerFault.failed('${e.runtimeType}'));
    } finally {
      http.close(force: true);
    }
  }

  static final _log = Logger('wyrm.login');
}

final class _GatewaySession implements WyrmSession {
  _GatewaySession(this._gw, this._client, this.base);

  final WyrmGateway _gw;
  final ReconnectingClient _client;

  @override
  final GatewayAddress base;

  @override
  WyrmApi get api => _client;

  @override
  Stream<bool> get connection => _client.connection;

  @override
  Future<GatewayIdentity> identity() => _gw.identity();

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
  Future<String> addDevice({
    required String site,
    required String user,
    required String name,
    required DevicePlatform platform,
    required DeviceAlg alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => _gw.addDevice(
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

/// One part of the gateway field as a URL: a URL without a scheme gets
/// `http://`; null when it is no `http`/`https` URL with a host.
Uri? _urlOf(String part) => switch (Uri.tryParse(
  part.contains('://') ? part : 'http://$part',
)) {
  final u?
      when u.host.isNotEmpty && (u.isScheme('http') || u.isScheme('https')) =>
    u,
  _ => null,
};

/// The parts of the gateway field, trimmed, none empty.
Iterable<String> _partsOf(String text) =>
    text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);

/// Splits the gateway field into addresses: one, or several separated by
/// commas for a site with a standby broker (ADR 0036). A URL without a
/// scheme gets `http://`. A part that is no URL, or that holds
/// `user:password@` ([gatewayProblemOf] says so), gives no address.
List<GatewayAddress> parseGateways(String text) => [
  for (final part in _partsOf(text))
    if (_urlOf(part) case final u? when u.userInfo.isEmpty) GatewayAddress._(u),
];

/// What is wrong with the gateway field [text]; null when every part is an
/// address.
GatewayFieldProblem? gatewayProblemOf(String? text) {
  final parts = _partsOf(text ?? '').toList();
  if (parts.isEmpty) {
    return GatewayFieldProblem.empty;
  }
  final urls = [for (final p in parts) _urlOf(p)];
  if (urls.any((u) => u?.userInfo.isNotEmpty ?? false)) {
    return GatewayFieldProblem.credentials;
  }
  return urls.contains(null) ? GatewayFieldProblem.invalid : null;
}

/// `user:password@` (or `user@`) of one part of the gateway field, with or
/// without its scheme: as `Uri` reads it, up to the last `@` before the
/// path, the query or the fragment (a password may hold `@` and spaces).
final _fieldUserInfo = RegExp(
  r'^(\s*(?:[A-Za-z][A-Za-z0-9+.-]*://)?)[^/?#]*@',
);

/// The gateway field [text] without the `user:password@` of any part: an
/// older file is read with this. Every part keeps its place; a part
/// without credentials stays as it was typed. A field typed now is kept
/// only when it holds no credentials at all ([gatewayProblemOf]).
String gatewayFieldWithoutCredentials(String text) => [
  for (final part in text.split(','))
    part.replaceFirstMapped(
      _fieldUserInfo,
      (m) => m.group(1)!,
    ),
].join(',');
