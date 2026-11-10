import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/problems/actions/add_problem_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:localization/localization.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/panel_fault.dart';

import 'dialogs/error_dialogs.dart';

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
  final e = faultOf(error, stack, step: library, screen: panel);
  return e.copyWith(
    title: panel == null
        ? S.current.faultUncaught
        : S.current.faultProblem(panel),
    message: S.current.errFaultMessage,
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
          text: detailsText(e, detailsContextOf(store.state), report: true),
        ),
      ),
    );
    store.dispatchSync(
      ShowNoticeAction(S.current.errCopied, detail: S.current.errReportCopied),
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

  void report(Object error, StackTrace? stack, {String? library}) {
    final line = faultLine(error);
    final now = DateTime.now();
    if (line == last && now.difference(lastAt) < const Duration(seconds: 2)) {
      return;
    }
    last = line;
    lastAt = now;
    debugPrint('uncaught: ${faultLine(error)}');
    // After the frame: a fault raised while building must not dispatch
    // into a tree that is being built.
    scheduleMicrotask(() {
      try {
        store.dispatchSync(
          AddProblemAction(uncaughtFault(error, stack, library: library)),
        );
      } on Object catch (e) {
        debugPrint('the fault could not be added to Problems: $e');
      }
    });
  }

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
