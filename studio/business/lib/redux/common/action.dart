import 'package:async_redux/async_redux.dart';
import 'package:flutter/foundation.dart' show mustCallSuper;

import 'package:models/studio_error.dart';

import '../../dependencies.dart';
import '../../environment.dart';
import '../../wyrm/failures.dart';
import '../app_state.dart';
import '../problems/actions/add_problem_action.dart';

abstract class Action extends ReduxAction<AppState> with Selectors {
  Action({this.quiet = false});

  /// Injected services for this store (see [AppDependencies]).
  AppDependencies get deps => store.dependencies! as AppDependencies;

  /// The store environment (base URL, prod/dev, …).
  Environment get env => store.environment! as Environment;

  /// Set on one dispatch — `dispatch(RetrieveLinksAction(quiet: true))` —
  /// when nobody asked for this run: a failure still fails the dispatch,
  /// but it opens no dialog. It becomes a toast and a line in Problems
  /// (docs/design/specs/errors.md §4). An action offers it by passing
  /// `super.quiet` from its constructor.
  ///
  /// A read the app starts by itself (the log-in preload,
  /// docs/design/specs/login.md §5.1) may fail on rights the user does not
  /// have or finish after the page that started it is gone; a dialog then
  /// would be about something the user never did. The same action dispatched
  /// from a screen keeps its dialog.
  final bool quiet;

  /// A fresh copy of this action, for *Try again* in the dialog, the toast
  /// and the Problems drawer; null (the default) when the call cannot be
  /// repeated as it was.
  Action? again() => null;

  /// The load action of the screen this action belongs to, for *Refresh*
  /// after a `not_found`; null when there is none.
  Action? reload() => null;

  /// The name of this action as a step, for a fault in Studio:
  /// `RetrieveLinksAction` reads `retrieve links`.
  String get stepName => '$runtimeType'
      .replaceFirst(RegExp(r'Action$'), '')
      .replaceFirst(RegExp('^_'), '')
      .replaceAllMapped(
        RegExp('(?<=[a-z0-9])[A-Z]'),
        (m) => ' ${m.group(0)}',
      )
      .toLowerCase();

  StudioError? _failed;

  /// Every failure leaves as one [StudioException]: a refusal keeps its
  /// status, anything else is a fault in Studio with its report. The error
  /// is given its id, time, site, title, and what *Try again* and
  /// *Refresh* dispatch; [after] then adds it to Problems.
  @override
  Object? wrapError(Object error, StackTrace stackTrace) {
    final wrapped = super.wrapError(error, stackTrace);
    if (wrapped == null) {
      return null;
    }
    final thrown = studioExceptionOf(wrapped, stackTrace, step: stepName);
    final e = thrown.error;
    final filled = e.copyWith(
      id: e.id == 0 ? nextErrorId() : e.id,
      at: e.at ?? DateTime.now(),
      site: e.site ?? site.viewed,
      quiet: e.quiet || quiet,
      retry: e.retry ?? (again() == null ? null : () => again()!),
      reload: e.reload ?? (reload() == null ? null : () => reload()!),
    );
    _failed = filled;
    return thrown.withError(
      filled,
      ifOpenDialog: thrown.ifOpenDialog && !filled.quiet,
    );
  }

  @mustCallSuper
  @override
  void after() {
    super.after();
    if (_failed case final e?) {
      _failed = null;
      dispatchSync(AddProblemAction(e));
    }
  }
}

/// The action is drawn while it runs: a selector may ask whether it is in
/// flight, `waiting.on<MyAction>()` (see `Waiting`, `common/waiting.dart`).
///
/// **A marker, with no hook of its own.** Through async_redux 29 this mixin
/// filed the action in `Wait` in `before()` and took it out in `after()`.
/// Since 30 the store knows every action in progress by itself and tells
/// the widgets that asked about its type when it starts and when it ends,
/// so there is nothing to raise and nothing a mixin that does not chain
/// `super.after()` can leave up.
///
/// What is left is the claim, and `Waiting.on` takes only a type that
/// makes it. It drives an indicator; it does not decide whether the screen
/// is usable meanwhile. A background refresh, a poll or a paginating load
/// that no screen draws does not mix it in, and then nothing can ask about
/// it by accident.
///
/// `frx add-action -k waiting` still puts it **last** in the `with` clause
/// and `frx doctor` still checks that; the order no longer matters to the
/// wait, and it is kept so that the generated form needs no edit.
mixin WaitingAction on ReduxAction<AppState> {}

/// The user is blocked on this: the modal barrier covers the app while it runs.
///
/// **Separate from [WaitingAction] because "is in flight" and "the screen is
/// unusable" are different claims,** and the second is the one nobody should
/// make by accident: every action that wants an indicator reaches for
/// [WaitingAction], and if that also meant the barrier, the first background
/// operation anyone adds would blank the app.
///
/// **The mixin alone does not raise the barrier.** The store compares exact
/// runtime types (`Store.isWaiting`), so no question can be put about "any
/// action with this mixin". The barrier asks about the types listed in
/// `blockingActions` (`app/lib/common/blocking_actions.dart`); an action
/// with this mixin goes into that list, and
/// `app/test/blocking_actions_test.dart` fails while one is missing from it
/// or one is listed without the mixin.
mixin BlockingAction on WaitingAction {}
