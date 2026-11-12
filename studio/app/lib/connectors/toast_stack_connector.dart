import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/dismiss_toast_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/toast_stack.dart';

import '../dialogs/error_dialogs.dart';
import '../errors.dart';

/// The toasts of quiet failures and of successes
/// (docs/design/specs/errors.md §4), over every page. Hidden while the
/// Problems drawer is open: the same failures are listed there.
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
        labels: ToastLabels(
          details: S.current.errDetails,
          retry: S.current.errTryAgain,
          dismiss: S.current.toastDismiss,
          region: S.current.toastNotifications,
          hidesIn: S.current.toastHidesIn,
        ),
        onDismiss: vm.onDismiss,
        onRetry: vm.onRetry,
        onDetails: (id) {
          vm.onDismiss(id);
          unawaited(showProblemDetails(context, id));
        },
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ToastStackConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final failed = {for (final e in problems.items) e.id: e};
    final toasts = <ToastVm>[
      for (final id in problems.toasts)
        if (failed[id] case final e?) errorToastVm(e),
      for (final n in problems.notices)
        ToastVm(
          id: n.id,
          tone: .good,
          title: n.title,
          line: n.detail ?? '',
          seconds: 3,
        ),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return _Vm(
      toasts: problems.open ? const [] : toasts,
      onDismiss: (id) => dispatchSync(DismissToastAction(id)),
      onRetry: (id) => unawaited(dispatchAndWait(RetryProblemAction(id))),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
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
