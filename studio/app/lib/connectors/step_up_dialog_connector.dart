import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/cancel_step_up_action.dart';
import 'package:business/redux/device/actions/confirm_step_up_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/step_up_dialog.dart';

import '../common/unlock.dart';

/// The step-up over everything (ADR 0050 §1.3, board `UnlockStepUp`): shown
/// while a request refused with `confirm_required` waits, one at a time.
/// Placed in the app's builder above the router, so it shows on any page.
class StepUpDialogConnector extends StatelessWidget {
  const StepUpDialogConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) {
      final d = vm.dialog;
      if (d == null) {
        return const SizedBox.shrink();
      }
      // Its own overlay: the password field needs one, and this sits above
      // the router's.
      return Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Material(
              type: MaterialType.transparency,
              child: ColoredBox(
                color: StepUpDialog.barrier,
                child: Center(
                  child: StepUpDialog(
                    vm: d,
                    onDevice: vm.onDevice,
                    onPassword: vm.onPassword,
                    onCancel: vm.onCancel,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, StepUpDialogConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final pending = state.device.stepUp;
    final s = S.current;
    final siteName = site.name ?? '';
    final name = unlockName(device.kind);
    final reason = s.unlockConfirmPrompt(siteName);
    String? error(String? e) => switch (e) {
      null => null,
      'bad_password' => s.lockWrongPassword,
      final e
          when e.startsWith('cancelled') ||
              e.startsWith('locked') ||
              e.startsWith('biometrics') =>
        s.stepUpStopped(name),
      final e => s.stepUpRefused(siteName, e),
    };
    return _Vm(
      dialog: pending == null
          ? null
          : StepUpDialogVm(
              title: s.stepUpTitle,
              lead: s.stepUpLead(pending.lines.length, siteName),
              lines: [
                for (final l in pending.lines)
                  StepUpLineVm(level: l.level, text: l.text, key: l.key),
              ],
              glyph: unlockGlyph(device.kind),
              device: pending.busy
                  ? s.stepUpWaiting(name)
                  : s.stepUpDevice(
                      name,
                      siteName,
                      unlockDevice(devicePlatform()),
                    ),
              confirm: s.stepUpConfirmWith(name),
              passwordConfirm: s.stepUpConfirm,
              usePassword: s.unlockUsePassword,
              cancel: s.cancel,
              passwordLabel: s.unlockPasswordFor(
                (login.user ?? '').trim(),
              ),
              busy: pending.busy,
              error: error(pending.error),
              passwordOnly: pending.passwordOnly,
            ),
      onDevice: () =>
          unawaited(dispatchAndWait(ConfirmStepUpAction(reason: reason))),
      onPassword: (p) => unawaited(
        dispatchAndWait(ConfirmStepUpAction(reason: reason, password: p)),
      ),
      onCancel: () => dispatchSync(CancelStepUpAction()),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.dialog,
    required this.onDevice,
    required this.onPassword,
    required this.onCancel,
  }) : super(equals: [dialog]);

  final StepUpDialogVm? dialog;
  final VoidCallback onDevice;
  final ValueChanged<String> onPassword;
  final VoidCallback onCancel;
}
