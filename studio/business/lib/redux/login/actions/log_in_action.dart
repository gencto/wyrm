import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/session.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../session/models/session_state.dart';
import '../../site/models/site_state.dart';

/// Logs in to a WYRM user gateway (docs/studio.md §5.1).
///
/// 1. `WyrmGateway.loginAny` on the typed gateway URL(s) — several, comma
///    separated, for a site with a standby broker (ADR 0036).
/// 2. `/api/me` → who the user is on which site, into `site`.
/// 3. The reconnecting client becomes `deps.wyrm` for every later call.
/// 4. `session.token` is written last; the auth guard reacts to it and leaves
///    the log-in page by itself, so no navigation is dispatched here.
///
/// The password leaves the login slice in the same reduce that writes the
/// token: a state where the user is logged in and the form still holds the
/// password is one no screen should observe. The gateway URL and the user
/// stay, so the next log-in starts from them.
class LogInAction extends Action with WaitingAction, BlockingAction {
  @override
  Future<AppState> reduce() async {
    final gateways = parseGateways(login.gateway ?? '');
    final user = (login.user ?? '').trim();
    final password = login.password ?? '';
    if (gateways.isEmpty) {
      throw const UserException(
        'Type the gateway URL, e.g. http://127.0.0.1:8445.',
      );
    }
    if (user.isEmpty || password.isEmpty) {
      throw const UserException('Type the user and the password.');
    }

    final WyrmSession session;
    try {
      session = await deps.login.open(gateways, user: user, password: password);
    } on WyrmException catch (e) {
      throw UserException(
        e.status == StatusCode.of(Status.permissionDenied)
            ? 'The gateway refused the user or the password.'
            : 'Cannot reach the gateway.',
        reason: e.message,
      );
    } on Object catch (e) {
      throw UserException('Cannot reach the gateway.', reason: '$e');
    }

    final WhoAmI me;
    try {
      me = await session.me();
    } on Object catch (e) {
      await session.close();
      throw UserException('The gateway did not say who you are.', reason: '$e');
    }
    await deps.attach(session);

    return state.copyWith(
      session: SessionState(token: me.subject.isEmpty ? user : me.subject),
      site: SiteState(
        gateway: session.base.toString(),
        user: me.subject.isEmpty ? user : me.subject,
        name: me.site,
        role: me.roles.isEmpty ? me.max : me.roles.join(', '),
        connected: true,
      ),
      login: state.login.copyWith(password: null),
    );
  }
}
