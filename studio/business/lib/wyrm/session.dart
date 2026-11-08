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

  /// Close the client and the HTTP connection.
  Future<void> close();
}

/// Opens a [WyrmSession]: the first of the gateways that accepts the login.
abstract interface class WyrmLogin {
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
  });
}

/// The real login: `WyrmGateway.loginAny` and a reconnecting client.
final class GatewayLogin implements WyrmLogin {
  const GatewayLogin();

  @override
  Future<WyrmSession> open(
    List<Uri> gateways, {
    required String user,
    required String password,
  }) async {
    final gw = await WyrmGateway.loginAny(
      gateways,
      user: user,
      password: password,
    );
    try {
      final client = await gw.client();
      return _GatewaySession(gw, client);
    } catch (_) {
      gw.dispose();
      rethrow;
    }
  }
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
