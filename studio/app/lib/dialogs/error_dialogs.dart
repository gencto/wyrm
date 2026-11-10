import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/access/actions/set_selected_action.dart';
import 'package:business/redux/access/actions/set_tab_action.dart'
    as access_slice;
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/add_problem_action.dart';
import 'package:business/redux/problems/actions/mark_problem_shown_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/redux/system/actions/set_tab_action.dart'
    as system_slice;
import 'package:business/wyrm/failures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:models/studio_error.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/pages/system_page.dart';

import '../errors.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// How an error dialog was closed.
enum _Closed { primary, secondary, dismissed }

/// One dialog at a time (docs/design/specs/errors.md §2): an error that
/// arrives while one is open is in Problems already and raises the counter.
var _open = false;

/// Whether an error dialog is on screen (tests).
bool get errorDialogOpen => _open;

/// Who is logged in where, for Details and *Copy details*.
DetailsContext detailsContextOf(AppState state) => DetailsContext(
  user: state.site.user,
  role: state.site.role,
  gateway: state.site.gateway,
  studio: studioAbout,
);

/// Puts the details of [e] (its report, for a fault in Studio) on the
/// clipboard and says so. Never a value, a token or a password: a
/// `StudioError` holds none, and its message is redacted.
void copyErrorDetails(Store<AppState> store, StudioError e) {
  final report = e.report != null;
  unawaited(
    Clipboard.setData(
      ClipboardData(
        text: detailsText(e, detailsContextOf(store.state), report: report),
      ),
    ),
  );
  store.dispatchSync(
    ShowNoticeAction(
      S.current.errCopied,
      detail: report ? S.current.errReportCopied : S.current.errDetailsCopied,
    ),
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
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  final thrown = studioExceptionOf(userException, null);
  var e = thrown.error;
  if (userException is! StudioException) {
    // It did not come through an action of ours: it is not in Problems yet.
    e = wordError(e.copyWith(id: nextErrorId(), at: DateTime.now()));
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
Future<void> showProblemDetails(BuildContext context, int id) async {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
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
  final primary = errorPrimary(e, readOnly: readOnly);
  final _Closed closed;
  try {
    closed =
        await ErrorDialog.show<_Closed>(
          context,
          (dialog) => ErrorDialog(
            vm: errorDialogVm(
              e,
              user: store.state.site.user,
              role: store.state.site.role,
              gateway: store.state.site.gateway,
              readOnly: readOnly,
            ),
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
        case .retry:
          unawaited(store.dispatchAndWait(RetryProblemAction(e.id)));
        case .refresh:
          unawaited(
            store.dispatchAndWait(RetryProblemAction(e.id, refresh: true)),
          );
        case .log:
          // System › Log, read again: the lines around the failure are the
          // newest ones.
          store
            ..dispatchSync(system_slice.SetTabAction(SystemPage.logTab))
            ..dispatch(GoAction.navigate(const SystemRoute()));
          unawaited(store.dispatchAndWait(RetrieveSystemLogAction()));
        case .ok || .form:
          // Back to the form: the dialog that held the form is under this
          // one and marks the field itself (`refusedField`).
          break;
      }
    case _Closed.secondary:
      if (e.kind == .rights) {
        // Access, on the user's own line.
        store
          ..dispatchSync(access_slice.SetTabAction('users'))
          ..dispatchSync(SetSelectedAction(store.state.site.user))
          ..dispatch(GoAction.navigate(const AccessRoute()));
      }
    case _Closed.dismissed:
      break;
  }
}

/// The field a failed dispatch names, with the broker's message for the
/// line under it: `(poll_rate, 0 is below the minimum of 100 ms.)`. Null
/// when [status] did not fail on a named parameter. The form that
/// dispatched puts it under the field and focuses it, so *Back to the
/// form* lands there (errors.md §3).
(String, String)? refusedField(ActionStatus status) {
  final e = switch (status.originalError) {
    final StudioException x => x.error,
    _ => switch (status.wrappedError) {
      final StudioException x => x.error,
      _ => null,
    },
  };
  final field = e?.field;
  if (e == null || field == null) {
    return null;
  }
  final rest = e.message.replaceFirst(
    RegExp('^\\s*${RegExp.escape(field)}\\s*:\\s*'),
    '',
  );
  return (field, rest.isEmpty ? e.message : rest);
}
