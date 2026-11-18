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

  // A part that throws on every build would report itself on every frame,
  // and each report changes the state it is built from: the same fault is
  // taken once in two seconds.
  String? last;
  var lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether [error] is taken now: not the fault taken less than two
  /// seconds ago.
  bool fresh(Object error) {
    final line = faultLine(error);
    final now = DateTime.now();
    if (line == last && now.difference(lastAt) < const Duration(seconds: 2)) {
      return false;
    }
    last = line;
    lastAt = now;
    debugPrint('uncaught: $line');
    return true;
  }

  // A fault raised while building must not change the state of a tree that
  // is being built: the report's reducer is asynchronous (and says in the
  // log when it cannot add the fault). A fault handler waits for nothing:
  // it dispatches and returns.
  void report(Object error, StackTrace? stack, {String? library}) =>
      fresh(error)
      ? store.dispatch(
          ReportProblemAction(uncaughtFault(error, stack, library: library)),
        )
      : null;

  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Still printed for a developer.
    presentError?.call(details);
    if (!details.silent) {
      report(details.exception, details.stack, library: details.library);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error, stack);
    return true;
  };
}
