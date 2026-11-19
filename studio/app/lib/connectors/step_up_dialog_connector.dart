import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/cancel_step_up_action.dart';
import 'package:business/redux/device/actions/confirm_step_up_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/step_up_dialog.dart';
import 'package:ui/overlays/step_up_screen.dart';

import '../mappers/device_mappers.dart';
import '../mappers/log_in_mappers.dart';

/// The step-up over everything (ADR 0050 §1.3, board `UnlockStepUp`): shown
/// while a request refused with `confirm_required` waits, one at a time.
/// Placed in the app's builder above the router, so it shows on any page.
/// Typed values to `StepUpScreen`, which words them; one action per intent.
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
                  child: StepUpScreen(
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
  _Vm fromStore() => _Vm(
    dialog: switch (device.stepUp) {
      final pending? => StepUpScreenVm(
        site: site.name ?? '',
        user: login.formUser,
        lines: [for (final l in pending.lines) l.data],
        method: device.kind.method,
        os: hostPlatform().os,
        busy: pending.busy,
        problem: pending.error?.problem,
        passwordOnly: pending.passwordOnly,
      ),
      null => null,
    },
    onDevice: () => dispatch(ConfirmStepUpAction()),
    onPassword: (p) => dispatch(ConfirmStepUpAction(password: p)),
    onCancel: () => dispatchSync(CancelStepUpAction()),
  );
}

/// What the dialog draws ([dialog], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.dialog,
    required this.onDevice,
    required this.onPassword,
    required this.onCancel,
  }) : super(equals: [dialog]);

  final StepUpScreenVm? dialog;
  final VoidCallback onDevice;
  final ValueChanged<String> onPassword;
  final VoidCallback onCancel;
}
