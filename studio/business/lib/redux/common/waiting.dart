import 'action.dart';

/// async_redux's own question, as the store, an action and a view-model
/// factory all spell it: `isWaiting(MyAction)`, `isWaiting([A, B])`.
typedef IsWaiting = bool Function(
  Object actionOrTypeOrList, {
  Object? statusKey,
});

/// What is in flight: which actions the store is running now.
///
/// **It is not state.** Since async_redux 30 (`Wait` and `WaitAction` are
/// deprecated from 29.3.2) the store itself knows the actions in progress,
/// and nothing about them is written to `AppState`. So a selector over
/// `AppState` cannot say "busy"; whoever holds a store wraps its
/// `isWaiting` once and hands this to the selectors that draw a wait:
///
///     waiting                   // in an `Action` and in a `VmFactory`:
///                               // `Selectors` makes it from `isWaiting`
///     Waiting(store.isWaiting)  // beside a store (a dialog, a service)
///     Waiting.fixed({RetrieveLinksAction})  // in a test, no store at all
///
/// The selectors stay functions of their inputs: the state and this.
///
/// **Asking is what gets the widget told.** The store notifies its
/// listeners when an action starts and when it ends only for the types
/// somebody has asked about (`Store.isWaiting` records the type). A
/// view-model is a deterministic function of the state and of the answers
/// it got, so a type it did not ask about on its last run cannot change
/// what it returns, and one it did ask about is recorded: the first frame
/// of a wait is never missed. Do not keep an answer from one run for the
/// next; ask again.
final class Waiting {
  /// Asks [_ask] each time: nothing is kept between two questions.
  const Waiting(this._ask);

  /// Nothing is in flight, and nothing will be.
  const Waiting.none() : _ask = _never;

  /// Nobody said what is in flight: for a view made from a state alone,
  /// which draws no wait. Asking it is a fault in Studio: an assertion
  /// fails, so a selector that starts to read a wait there fails its first
  /// test. A release build answers "not in flight".
  const Waiting.unasked() : _ask = _unasked;

  /// Exactly [types] are in flight: for a test of a selector or a view.
  factory Waiting.fixed(Iterable<Type> types) {
    final running = types.toSet();
    return Waiting(
      (asked, {statusKey}) => switch (asked) {
        final Type t => running.contains(t),
        final Iterable<Object?> list => list.any(running.contains),
        _ => false,
      },
    );
  }

  final IsWaiting _ask;

  /// The question itself, as async_redux spells it: for a holder that
  /// passes a [Waiting] it was given on (`WaitingGiven`).
  bool ask(Object actionOrTypeOrList, {Object? statusKey}) =>
      _ask(actionOrTypeOrList, statusKey: statusKey);

  /// An action of exactly the type [T] is in flight. The store compares
  /// runtime types, so a base class or a mixin never answers true; only an
  /// action that says it is drawn ([WaitingAction]) may be asked about.
  bool on<T extends WaitingAction>() => _ask(T);

  /// An action of one of [types] is in flight.
  bool any(List<Type> types) => types.isNotEmpty && _ask(types);
}

bool _never(Object actionOrTypeOrList, {Object? statusKey}) => false;

bool _unasked(Object actionOrTypeOrList, {Object? statusKey}) {
  assert(
    false,
    'A wait ($actionOrTypeOrList) was asked of a view made from a state '
    'alone. Hand it a Waiting made from the store.',
  );
  return false;
}
