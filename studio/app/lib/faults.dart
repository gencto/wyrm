import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/report_problem_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:models/error_call.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/panel_fault.dart';

import 'dialogs/error_dialogs.dart';
import 'mappers/error_mappers.dart';

/// A fault outside any action (a widget that threw while building, a
/// callback, a future nobody awaited) as a quiet problem of kind `studio`:
/// a toast and a line in Problems, never a dialog
/// (docs/design/specs/errors.md §5).
StudioError uncaughtFault(
  Object error,
  StackTrace? stack, {
  String? panel,
  String? library,
}) {
  final e = faultOf(
    error,
    stack,
    step: library == null ? null : ErrorCall.named(library),
    screen: panel,
  );
  // `ui` says what it is when it draws it: a fault in the background, or
  // the panel that could not be drawn
  return e.copyWith(
    report: e.report?.copyWith(uncaught: true),
    quiet: true,
  );
}

/// Sets what replaces a widget that threw while building, and where every
/// uncaught fault goes: into Problems of [store], and the log.
///
/// The card is used in profile and release builds; a debug build keeps
/// Flutter's red screen, so a developer sees the fault where it is, unless
/// [cardInDebug] (tests).
void installFaultHooks(Store<AppState> store, {bool cardInDebug = false}) {
  PanelFault.describe = faultLine;
  PanelFault.copyReport = (details, panel) {
    final e = uncaughtFault(
      details.exception,
      details.stack,
      panel: panel,
      library: details.library,
    ).copyWith(at: DateTime.now());
    unawaited(
      Clipboard.setData(
        ClipboardData(
          text: e.said.details(
            errorContextOf(store.state),
            redact: redact,
            report: true,
          ),
        ),
      ),
    );
    store.dispatchSync(
      ShowNoticeAction(.reportCopied),
    );
  };
  if (!kDebugMode || cardInDebug) {
    ErrorWidget.builder = PanelFault.builder;
  }

  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Still printed for a developer.
    presentError?.call(details);
    // A handler waits for nothing: it dispatches and returns. The same
    // fault again within two seconds is not taken again (the action says
    // so), and it says the fault in the log.
    if (!details.silent) {
      store.dispatchSync(
        ReportProblemAction(
          uncaughtFault(
            details.exception,
            details.stack,
            library: details.library,
          ),
        ),
      );
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    store.dispatchSync(ReportProblemAction(uncaughtFault(error, stack)));
    return true;
  };
}
