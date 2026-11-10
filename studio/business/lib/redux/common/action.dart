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
    final filled = deps.wording(
      e.copyWith(
        id: e.id == 0 ? nextErrorId() : e.id,
        at: e.at ?? DateTime.now(),
        site: e.site ?? site.viewed,
        quiet: e.quiet || quiet,
        retry: e.retry ?? (again() == null ? null : () => again()!),
        reload: e.reload ?? (reload() == null ? null : () => reload()!),
      ),
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

/// Registers the action in `Wait` while it runs, so a selector can read that it
/// is in flight — `_state.wait.isWaitingForType<MyAction>()`.
///
/// That is all it says. It drives an indicator; it does not decide whether the
/// screen is usable meanwhile. A background refresh, a poll or a paginating
/// load wants exactly this and nothing more.
///
/// **Both hooks call `super`, and that is load-bearing.** Dart gives a class
/// one `after()` — the last mixin's. Through async_redux 28.1, `NonReentrant`,
/// `Throttle` and `Fresh` overrode it to release their own lock *without*
/// calling `super.after()`, so in `with WaitingAction, NonReentrant` this
/// mixin's `after()` was never reached: the barrier went up and never came
/// down, and every widget reading `isWaitingForType<T>()` stayed disabled for
/// the rest of the session. Reversing the pair only moved the loss — then it
/// was the reentrancy lock that was never released.
///
/// Since 28.3.1 every mixin async_redux declares chains (this package requires
/// ≥ 28.4), and this one always did: it cleans up and passes the baton, and
/// `add-action` puts it **last** in the `with` clause so it is the one Dart
/// calls — a rule that costs nothing and covers the next mixin that does not
/// chain. `frx doctor` checks both halves.
///
/// Both hooks are `@mustCallSuper`, as async_redux's own are from 28.4: an
/// action that writes its own `after()` and forgets `super` is the other way
/// to end the chain, and this way the analyzer says so where it is written,
/// before `doctor` does.
///
/// `before()` returns `Future<void>` rather than `void` for a narrower reason:
/// `CheckInternet` declares `Future<void> before()`, and a `void` override of
/// it is a compile error — which is what a `WaitingAction` placed last, in
/// front of nothing, would otherwise be.
mixin WaitingAction on ReduxAction<AppState> {
  bool get notifyBefore => true;
  bool get notifyAfter => false;

  @mustCallSuper
  @override
  Future<void> before() async {
    // Synchronous — the body runs to the first `await` before the store gets
    // its future back, so the indicator is up in the same frame as the tap.
    dispatchSync(WaitAction.add(this), notify: notifyBefore);
    await super.before();
  }

  @mustCallSuper
  @override
  void after() {
    // Locks first, barrier second: whoever wakes on the barrier coming down
    // finds a dispatchable action rather than one still holding its own lock.
    super.after();
    dispatchSync(WaitAction.remove(this), notify: notifyAfter);
  }
}

/// The user is blocked on this: the modal barrier covers the app while it runs.
///
/// **Separate from [WaitingAction] because "is in flight" and "the screen is
/// unusable" are different claims,** and the second is the one nobody should
/// make by accident. The barrier asks `isWaitingForType<BlockingAction>()` —
/// `WaitAction.add(this)` files the action itself as the flag and
/// `isWaitingForType<T>` tests `flag is T`, so a mixin answers as readily as a
/// class, and the set needs no list anywhere.
///
/// Keyed on this rather than on `Wait` membership because every async action
/// that wants an indicator reaches for [WaitingAction]; if that also meant the
/// barrier, the first background operation anyone adds would blank the app.
/// Opting in is a sentence you write on purpose.
mixin BlockingAction on WaitingAction {}
