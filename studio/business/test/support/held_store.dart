import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';

/// A store a test can tell "an action of this type is in flight", for a
/// test of what a screen draws while it waits.
///
/// The store answers `isWaiting` from the actions it runs, and a wait is no
/// part of the state, so a test cannot write one into an `AppState`. Where
/// the action can be run and held (a fake gateway with a gate), run it:
/// that is the real thing. This store is for the rest: an action whose work
/// cannot be stopped half way in a test, drawn at one step of it.
///
/// It does not test that the store tells its listeners (it tells them
/// itself here): `waiting_action_test.dart` does, on a plain [Store].
class HeldStore extends Store<AppState> {
  HeldStore({
    required super.initialState,
    super.dependencies,
    super.actionObservers,
    super.globalErrorObserver,
  });

  final _held = <Type>{};

  /// Says an action of [type] is in flight ([on]) or has ended, and tells
  /// the listeners, as the store does for a type it was asked about.
  void hold(Type type, {bool on = true}) {
    on ? _held.add(type) : _held.remove(type);
    dispatchSync(_Tell());
  }

  @override
  bool isWaiting(Object actionOrTypeOrList, {Object? statusKey}) =>
      switch (actionOrTypeOrList) {
        final Type t => _held.contains(t),
        final Iterable<Object?> list => list.any(_held.contains),
        _ => false,
      } ||
      super.isWaiting(actionOrTypeOrList, statusKey: statusKey);
}

/// An event with the state as it is: a copy, since the store tells nobody
/// about the very same object.
class _Tell extends ReduxAction<AppState> {
  @override
  AppState reduce() => state.copyWith();
}
