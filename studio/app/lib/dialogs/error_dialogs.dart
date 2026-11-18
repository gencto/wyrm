import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/access/actions/set_selected_action.dart';
import 'package:business/redux/access/actions/set_tab_action.dart'
    as access_slice;
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/add_problem_action.dart';
import 'package:business/redux/problems/actions/dismiss_toast_action.dart';
import 'package:business/redux/problems/actions/mark_problem_shown_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/system/actions/aim_log_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/wyrm/error_view.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/access_tab.dart';
import 'package:models/studio_error.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/dialogs/error_said.dart';

import '../common/app_store.dart';
import '../mappers/error_mappers.dart';
import '../navigation/app_router.dart';
import '../navigation/go_after_action.dart';

/// How an error dialog was closed.
enum _Closed { primary, secondary, dismissed }

/// One dialog at a time (docs/design/specs/errors.md §2): an error that
/// arrives while one is open is in Problems already and raises the counter.
var _open = false;

/// Whether an error dialog is on screen (tests).
bool get errorDialogOpen => _open;

/// Who is logged in where, for Details and *Copy details*.
ErrorContext errorContextOf(AppState state) => ErrorContext(
  user: state.site.user,
  role: state.site.role,
  gateway: state.site.gateway?.text,
  about: studioAbout,
);

/// Puts the details of [e] (its report, for a fault in Studio) on the
/// clipboard and says so. Never a value, a token or a password: a
/// `StudioError` holds none, and its message is redacted.
void copyErrorDetails(Store<AppState> store, StudioError e) {
  final report = e.report != null;
  unawaited(
    Clipboard.setData(
      ClipboardData(
        text: e.said.details(
          errorContextOf(store.state),
          redact: redact,
          report: report,
        ),
      ),
    ),
  );
  store.dispatchSync(
    ShowNoticeAction(report ? .reportCopied : .detailsCopied),
  );
}

/// The dialog of every `UserException` the store queues: handed to
/// `ExceptionDialog(onShowUserExceptionDialog:)` in `app.dart`. Replaces
/// the Material `AlertDialog` (errors.md §3).
///
/// A `StudioException` shows its error; a plain `UserException` (from a
/// package) is shown in the same card with its title and reason, in the
/// `studio` styling, with OK.
void showUserException({
  required BuildContext context,
  required UserException userException,
  required bool useLocalContext,
}) {
  final store = AppStore.of(context);
  final thrown = studioExceptionOf(userException, null);
  var e = thrown.error;
  if (userException is! StudioException) {
    // It did not come through an action of ours: it is not in Problems yet.
    e = e.copyWith(id: nextErrorId(), at: DateTime.now());
    store.dispatchSync(AddProblemAction(e));
  }
  if (_open) {
    return;
  }
  final ctx = useLocalContext
      ? context
      : (NavigateAction.navigatorKey?.currentContext ?? context);
  unawaited(
    _show(
      ctx,
      store,
      e,
      onOk: thrown.onOk,
      onCancel: thrown.onCancel,
    ),
  );
}

/// *Details* of a toast or of a card in Problems: the dialog of the problem
/// [id], read only. It repeats no write and counts nothing down.
/// The details of the toast [id]'s failure: the toast goes (one
/// dispatch), the dialog opens.
Future<void> showToastDetails(BuildContext context, int id) {
  AppStore.of(context).dispatchSync(DismissToastAction(id));
  return showProblemDetails(context, id);
}

Future<void> showProblemDetails(BuildContext context, int id) async {
  final store = AppStore.of(context);
  final e = store.state.problems.items.where((p) => p.id == id).firstOrNull;
  if (e == null || _open) {
    return;
  }
  final ctx = NavigateAction.navigatorKey?.currentContext ?? context;
  await _show(ctx, store, e, readOnly: true);
}

Future<void> _show(
  BuildContext context,
  Store<AppState> store,
  StudioError e, {
  bool readOnly = false,
  VoidCallback? onOk,
  VoidCallback? onCancel,
}) async {
  _open = true;
  if (!readOnly) {
    store.dispatchSync(MarkProblemShownAction(e.id));
  }
  final primary = e.action(readOnly: readOnly);
  final secondary = e.secondary(readOnly: readOnly);
  final _Closed closed;
  try {
    closed =
        await ErrorDialog.show<_Closed>(
          context,
          (dialog) => ErrorDialog(
            vm: e.dialog(errorContextOf(store.state), readOnly: readOnly),
            onPrimary: () => Navigator.of(dialog).pop(_Closed.primary),
            onSecondary: () => Navigator.of(dialog).pop(_Closed.secondary),
            onClose: () => Navigator.of(dialog).pop(_Closed.dismissed),
            onCopy: () => copyErrorDetails(store, e),
          ),
        ) ??
        _Closed.dismissed;
  } finally {
    _open = false;
  }
  // As a `UserException` always did: the main button is OK; the close
  // button and Esc are Cancel when there is one, else OK.
  switch (closed) {
    case _Closed.primary:
      onOk?.call();
    case _Closed.secondary || _Closed.dismissed:
      (onCancel ?? onOk)?.call();
  }
  // The dialog is closed first; then what its button stands for.
  switch (closed) {
    case _Closed.primary:
      switch (primary) {
        // The dialog is closed: what follows is awaited here, and the
        // dialog's own caller does not wait for it (`showUserException`).
        case .retry:
          await store.dispatchAndWait(RetryProblemAction(e.id));
        case .refresh:
          await store.dispatchAndWait(RetryProblemAction(e.id, refresh: true));
        case .log:
          // *Open the log*: the tab and its time in one state, its lines
          // read, then System.
          await store.dispatchAndWait(
            GoAfterAction(const SystemRoute(), [
              AimLogAction(e.at),
              RetrieveSystemLogAction(),
            ]),
          );
        case .ok || .form:
          // Back to the form: the form is under this dialog, with its
          // values; it marked the field itself when the dispatch failed
          // (`sendForm` in common/forms.dart, `ActionForm`).
          break;
      }
    case _Closed.secondary:
      if (secondary == .seeAccess) {
        // Access, on the user's own line: one action, the tab and the
        // user in one state, then the route.
        await store.dispatchAndWait(
          GoAfterAction(const AccessRoute(), [
            access_slice.SetTabAction(AccessTab.users),
            SetSelectedAction(store.state.site.user),
          ]),
        );
      }
    case _Closed.dismissed:
      break;
  }
}
