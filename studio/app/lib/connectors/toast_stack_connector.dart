import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/dismiss_toast_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/wyrm/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/toast_stack.dart';

import '../dialogs/error_dialogs.dart';
import '../errors.dart';
import '../mappers/notice_mappers.dart';

/// The toasts of quiet failures and of successes
/// (docs/design/specs/errors.md §4), over every page, in the order of the
/// selector `toasts` (none while the Problems drawer is open). `ToastStack`
/// words them; one action per intent.
class ToastStackConnector extends StatelessWidget {
  const ToastStackConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => SizedBox(
      width: vm.toasts.isEmpty ? 0 : ToastStack.width,
      child: ToastStack(
        toasts: vm.toasts,
        onDismiss: vm.onDismiss,
        onRetry: vm.onRetry,
        onDetails: (id) => unawaited(showToastDetails(context, id)),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ToastStackConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    toasts: [
      for (final t in toasts)
        switch (t) {
          ErrorToast(:final error) => errorToastVm(error),
          NoticeToast(:final notice) => notice.toast,
        },
    ],
    onDismiss: (id) => dispatchSync(DismissToastAction(id)),
    onRetry: (id) => dispatch(RetryProblemAction(id)),
  );
}

/// What the stack draws ([toasts], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.toasts,
    required this.onDismiss,
    required this.onRetry,
  }) : super(equals: [toasts]);

  /// Oldest first; ids of errors and notices come from one counter.
  final List<ToastVm> toasts;
  final ValueChanged<int> onDismiss;
  final ValueChanged<int> onRetry;
}
