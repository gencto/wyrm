import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:models/grant.dart';
import 'package:models/login_failure.dart';
import 'package:wyrm_client/wyrm_client.dart' hide Grant;

import '../../../wyrm/failures.dart';
import '../../../wyrm/session.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../session/models/session_state.dart';
import '../../site/models/site_state.dart';
import 'probe_gateway_action.dart';
import 'set_login_progress_action.dart';

/// Logs in to a WYRM user gateway (docs/studio.md §5.1).
///
/// 0. A timed probe of each gateway until one answers (`Reaching`); none →
///    [LoginFailure.unreachable]. `login.step` follows the three steps the
///    page shows (docs/design/specs/login.md §5).
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
///
/// Waiting, not blocking: the log-in page shows its own progress (the busy
/// button and the three steps, docs/design/specs/login.md §3.6–3.7), which
/// the modal barrier would blur over.
class LogInAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    final gateways = parseGateways(login.gateway ?? '');
    final user = (login.user ?? '').trim();
    final password = login.password ?? '';
    // An empty or malformed field is the form's to say, under the field
    // (docs/design/specs/errors.md §2: validation is inline, never a
    // dialog). The page validates before it dispatches; a dispatch that
    // comes without that changes nothing.
    if (gateways.isEmpty || user.isEmpty || password.isEmpty) {
      return state;
    }

    // 1. Reaching: the first gateway that answers a probe; the others are
    //    tried by `loginAny` in their turn too.
    dispatchSync(SetLoginProgressAction());
    final probes = <String, int>{};
    GatewayProbe? last;
    for (final g in gateways) {
      last = await deps.login.probe(g);
      probes[gatewayKey(g)] = last.ms ?? -1;
      if (last.answered) {
        break;
      }
    }
    if (last != null && !last.answered) {
      dispatchSync(
        SetLoginProgressAction(
          failure: LoginFailure.unreachable,
          reason: last.reason,
          probes: probes,
        ),
      );
      throw _unreachable(last.reason ?? '', gateways.first).withDialog(false);
    }

    // 2. Checking the user and the password.
    dispatchSync(SetLoginProgressAction(step: 1, probes: probes));
    final WyrmSession session;
    try {
      session = await deps.login.open(gateways, user: user, password: password);
    } on WyrmException catch (e) {
      final wrong = e.status == StatusCode.of(Status.permissionDenied);
      dispatchSync(
        SetLoginProgressAction(
          step: 1,
          failure: wrong ? LoginFailure.wrong : LoginFailure.unreachable,
          reason: e.message,
        ),
      );
      // The page shows both inline (spec §5), so no dialog.
      throw StudioException.refused(
        e,
        call: 'log_in',
        thing: '${gateways.first}',
      ).withDialog(false);
    } on Object catch (e) {
      dispatchSync(
        SetLoginProgressAction(
          step: 1,
          failure: LoginFailure.unreachable,
          reason: '$e',
        ),
      );
      throw _unreachable(faultLine(e), gateways.first).withDialog(false);
    }

    // 3. Reading the role and the sites.
    dispatchSync(SetLoginProgressAction(step: 2));
    final WhoAmI me;
    try {
      me = await session.me();
    } on Object catch (e) {
      await session.close();
      throw switch (e) {
        final WyrmException w => StudioException.refused(
          w,
          call: 'me',
          thing: '${gateways.first}',
        ),
        _ => StudioException.said(
          ErrorKind.reach,
          faultLine(e),
          call: 'me',
          thing: '${gateways.first}',
        ),
      };
    }
    await deps.attach(session);

    return state.copyWith(
      session: SessionState(token: me.subject.isEmpty ? user : me.subject),
      site: SiteState(
        gateway: session.base.toString(),
        user: me.subject.isEmpty ? user : me.subject,
        name: me.site,
        role: me.roles.isEmpty ? me.max : me.roles.join(', '),
        max: me.max,
        connected: true,
        grants: [for (final (k, p) in me.grants) Grant(key: k, level: p)].lock,
      ),
      login: state.login.copyWith(
        password: null,
        step: 0,
        failure: null,
        reason: null,
        recent: remembered(state.login.recent, login.gateway!),
        // The welcome's preload starts from its first step.
        preload: 0,
        preloadLate: const IListConst([]),
      ),
    );
  }
}

/// [gateway] in front of [recent], once, and at most five: the gateways that
/// logged in, newest first (docs/design/specs/login.md §6).
IList<String> remembered(IList<String> recent, String gateway) {
  final g = gateway.trim();
  return [g, ...recent.where((r) => r != g)].take(5).toIList();
}

/// No gateway answered: a `reach` error with what the probe said. The page
/// shows it itself (login.md §5), so it opens no dialog.
StudioException _unreachable(String reason, Object gateway) =>
    StudioException.said(
      ErrorKind.reach,
      reason,
      call: 'log_in',
      thing: '$gateway',
    );
