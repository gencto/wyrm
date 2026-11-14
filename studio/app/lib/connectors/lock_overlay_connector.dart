import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/note_activity_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/device/actions/unlock_with_password_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/lock_overlay.dart';

import '../common/unlock.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// The idle lock over the Studio shell [child] (ADR 0050 §1.4, board
/// `UnlockLock`), and the clock's touch on the person's input.
class LockOverlayConnector extends StatelessWidget {
  const LockOverlayConnector({required this.child, this.onLogOut, super.key});

  final Widget child;

  /// The shell's own log out (it also leaves the page); a plain
  /// `LogOutAction` without one.
  final VoidCallback? onLogOut;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LockOverlay(
      card: vm.card,
      onUnlock: vm.onUnlock,
      onPassword: vm.onPassword,
      onLogOut: onLogOut ?? vm.onLogOut,
      onActivity: vm.onActivity,
      child: child,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LockOverlayConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final d = state.device;
    final s = S.current;
    final siteName = site.name ?? '';
    final user = (login.user ?? '').trim();
    final name = unlockName(d.kind);
    final key = d.available && d.keyId != null && !d.stale;
    final kept = state.changes.view.length;
    return _Vm(
      card: !d.locked
          ? null
          : LockCardVm(
              title: s.lockTitle,
              text: s.lockText(user, siteName, d.lockAfter),
              glyph: unlockGlyph(d.kind),
              unlockLabel: s.unlockWith(name),
              kept: kept == 0 ? null : s.lockKept(kept),
              usePassword: s.unlockUsePassword,
              logOut: s.logOut,
              passwordLabel: s.unlockPasswordFor(user),
              unlock: s.lockUnlock,
              error: switch (d.lockError) {
                null => null,
                'bad_password' => s.lockWrongPassword,
                final e => e,
              },
              checking:
                  state.wait.isWaitingForType<UnlockWithDeviceAction>() ||
                  state.wait.isWaitingForType<UnlockWithPasswordAction>(),
              passwordOnly: !key,
            ),
      onUnlock: key
          ? () => unawaited(() async {
              await dispatchAndWait(
                UnlockWithDeviceAction(reason: s.unlockPrompt(siteName, user)),
              );
              // The gateway refused the key: Studio logged out, and the
              // log-in page says why.
              if (state.session.token == null) {
                dispatchSync(GoAction.replace(const LogInRoute()));
              }
            }())
          : null,
      onPassword: (p) =>
          unawaited(dispatchAndWait(UnlockWithPasswordAction(p))),
      onLogOut: () => unawaited(() async {
        await dispatchAndWait(LogOutAction());
        dispatchSync(GoAction.replace(const LogInRoute()));
      }()),
      onActivity: () => dispatchSync(NoteActivityAction()),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.card,
    required this.onUnlock,
    required this.onPassword,
    required this.onLogOut,
    required this.onActivity,
  }) : super(equals: [card, onUnlock != null]);

  final LockCardVm? card;
  final VoidCallback? onUnlock;
  final ValueChanged<String> onPassword;
  final VoidCallback onLogOut;
  final VoidCallback onActivity;
}
