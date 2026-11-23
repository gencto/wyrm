import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:flutter_test/flutter_test.dart';

/// What is in flight, since async_redux 30: the store's own record of the
/// actions in progress, read through `Waiting` (`common/waiting.dart`).
///
/// Through async_redux 29 `WaitingAction` filed the action in `Wait`
/// (`AppState.wait`) in `before()` and took it out in `after()`, and this
/// file pinned the ways that could go wrong: a mixin after it that did not
/// chain `super.after()`, or an action's own bare `after()`, left the flag
/// up for the rest of the session. `Wait` is deprecated from 29.3.2. The
/// store adds an action to its set when the dispatch starts and removes it
/// when it has ended, whatever the hooks do, so those defects have nothing
/// left to break; the probes stay and now say so.
///
/// The second half is what the move could have lost and did not: a widget
/// is told when a wait it draws starts and when it ends, although the state
/// does not change (the groups "the store tells its listeners" below).
Store<AppState> _store() => Store<AppState>(initialState: AppState.initial());

Waiting _waiting(Store<AppState> store) => Waiting(store.isWaiting);

/// The reduce body every probe shares: async, so the wait is observable.
mixin _Probe on ReduxAction<AppState> {
  static var runs = 0;

  @override
  Future<AppState?> reduce() async {
    _Probe.runs++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return null;
  }
}

/// The shape `frx add-action -k waiting -m nonReentrant` writes.
class NonReentrantProbe extends Action
    with NonReentrant, WaitingAction, _Probe {}

/// `-m throttle`.
class ThrottleProbe extends Action with Throttle, WaitingAction, _Probe {}

/// `-m fresh`.
class FreshProbe extends Action with Fresh, WaitingAction, _Probe {}

/// `-m checkInternet`: `CheckInternet` declares `Future<void> before()`.
/// The marker has no `before()` of its own any more, so there is nothing to
/// clash; this class existing is the assertion.
class CheckInternetProbe extends Action
    with CheckInternet, WaitingAction, _Probe {}

/// The template's own combination, which Dart pins the other way round:
/// `BlockingAction` is declared `on WaitingAction`, so it must follow it.
class BlockingProbe extends Action with WaitingAction, BlockingAction, _Probe {}

/// An action whose `after()` does not chain. Through async_redux 29 this
/// left its flag in `Wait` for ever (the only `after()` Dart runs is this
/// one, and the mixin's never took the flag out).
class _OwnAfter extends Action with NonReentrant, WaitingAction, _Probe {
  @override
  // The defect on purpose: the wait must come down all the same.
  // ignore: must_call_super
  void after() {}
}

/// And the other hook: a `before()` that does not chain. Through 29 the
/// flag was never raised, so the indicator never appeared.
class _OwnBefore extends Action with NonReentrant, WaitingAction, _Probe {
  @override
  // The same defect in the other hook, on purpose.
  Future<void> before() async {}
}

/// An action with real work in its own hooks that passes the chain on.
class _OwnHooksChained extends Action with NonReentrant, WaitingAction, _Probe {
  final ran = <String>[];

  @override
  Future<void> before() async {
    ran.add('before');
    await super.before();
  }

  @override
  void after() {
    ran.add('after');
    super.after();
  }
}

/// Runs until [gate] is completed, and changes no state.
class _Held extends Action with WaitingAction {
  _Held(this.gate);

  final Completer<void> gate;

  @override
  Future<AppState?> reduce() async {
    await gate.future;
    return null;
  }
}

/// The same, failing at the end.
class _HeldThenFails extends Action with WaitingAction {
  _HeldThenFails(this.gate);

  final Completer<void> gate;

  @override
  Future<AppState?> reduce() async {
    await gate.future;
    throw const UserException('no');
  }
}

/// Another type, which nothing asks about.
class _Other extends Action with WaitingAction {
  _Other(this.gate);

  final Completer<void> gate;

  @override
  Future<AppState?> reduce() async {
    await gate.future;
    return null;
  }
}

void main() {
  setUp(() => _Probe.runs = 0);

  group('the wait comes down', () {
    for (final probe in <String, Action Function()>{
      'NonReentrant': NonReentrantProbe.new,
      'Throttle': ThrottleProbe.new,
      'Fresh': FreshProbe.new,
      'BlockingAction': BlockingProbe.new,
    }.entries) {
      test('with ${probe.key}', () async {
        final store = _store();
        final action = probe.value();
        await store.dispatchAndWait(action);

        expect(
          _waiting(store).any([action.runtimeType]),
          isFalse,
          reason:
              '${action.runtimeType} finished and the store still has it '
              'in progress: every widget reading the wait stays disabled',
        );
      });
    }
  });

  test('it composes with a mixin that narrows before()', () {
    // Not dispatched — `CheckInternet.before()` reaches connectivity_plus,
    // which is not a thing to boot for this. Constructing it is the
    // assertion: the file would not load if the two did not compose.
    expect(CheckInternetProbe(), isA<WaitingAction>());
  });

  group('an action that writes its own hook', () {
    test('a bare after() no longer leaves the wait up', () async {
      final store = _store();
      final action = _OwnAfter();
      await store.dispatchAndWait(action);

      expect(
        _waiting(store).on<_OwnAfter>(),
        isFalse,
        reason:
            'the store takes an ended action out of its set by itself; '
            'no hook of the action is part of that',
      );
    });

    test('a bare before() no longer hides it', () async {
      final store = _store();
      final pending = store.dispatchAndWait(_OwnBefore());

      expect(_waiting(store).on<_OwnBefore>(), isTrue);
      await pending;
      expect(_waiting(store).on<_OwnBefore>(), isFalse);
    });

    test('chaining both is correct in both directions', () async {
      final store = _store();
      final action = _OwnHooksChained();
      final pending = store.dispatchAndWait(action);

      expect(_waiting(store).on<_OwnHooksChained>(), isTrue, reason: 'up');
      await pending;
      expect(
        _waiting(store).on<_OwnHooksChained>(),
        isFalse,
        reason: 'and down',
      );
      expect(action.ran, ['before', 'after'], reason: 'its own work ran too');
    });
  });

  test('the wait is up while the action runs', () async {
    // The other direction, or "comes down" would pass on a store that never
    // had it: the action is in progress as the dispatch returns, so the
    // indicator is up in the same frame as the tap.
    final store = _store();
    final pending = store.dispatchAndWait(NonReentrantProbe());

    expect(_waiting(store).on<NonReentrantProbe>(), isTrue);
    await pending;
  });

  test('NonReentrant still releases its own lock', () async {
    final store = _store();
    await store.dispatchAndWait(NonReentrantProbe());
    await store.dispatchAndWait(NonReentrantProbe());

    expect(
      _Probe.runs,
      2,
      reason:
          'the second dispatch was aborted — the non-reentrant key from '
          'the first was never released',
    );
  });

  test('NonReentrant still blocks a concurrent dispatch', () async {
    // And the lock is real while it is held, or the test above would pass on a
    // NonReentrant that had stopped working altogether.
    final store = _store();
    final first = store.dispatchAndWait(NonReentrantProbe());
    final second = store.dispatchAndWait(NonReentrantProbe());
    await Future.wait([first, second]);

    expect(_Probe.runs, 1);
  });

  group('Waiting asks for exact types', () {
    test('a type that runs answers, another does not', () async {
      final store = _store();
      final gate = Completer<void>();
      final pending = store.dispatchAndWait(_Held(gate));

      expect(_waiting(store).on<_Held>(), isTrue);
      expect(_waiting(store).on<_Other>(), isFalse);
      expect(_waiting(store).any([_Other, _Held]), isTrue);
      expect(_waiting(store).any([_Other]), isFalse);
      expect(_waiting(store).any(const []), isFalse);
      gate.complete();
      await pending;
    });

    test('a mixin is not a type the store answers for', () async {
      // Why the barrier asks about a list (`blockingActions`) and not about
      // `BlockingAction`: the store compares runtime types.
      final store = _store();
      final pending = store.dispatchAndWait(BlockingProbe());

      expect(store.isWaiting(BlockingAction), isFalse);
      expect(store.isWaiting(BlockingProbe), isTrue);
      await pending;
    });

    test('fixed, none and unasked', () {
      final w = Waiting.fixed({_Held});
      expect(w.on<_Held>(), isTrue);
      expect(w.on<_Other>(), isFalse);
      expect(w.any([_Other, _Held]), isTrue);
      expect(const Waiting.none().on<_Held>(), isFalse);
      expect(
        () => const Waiting.unasked().on<_Held>(),
        throwsA(isA<AssertionError>()),
        reason: 'a view made from a state alone must not draw a wait',
      );
    });
  });

  // What a connector sees. A `StoreConnector` makes its view-model again on
  // every event of `store.onChange` and builds its widget again when the
  // view-model differs. So "is the widget told" is "is there an event after
  // which the question has its new answer". The state is the same object
  // throughout: none of these actions changes it.
  group('the store tells its listeners', () {
    /// The answers a listener gets, one per event, asking as a view-model
    /// factory does: again on every run.
    List<bool> answers(Store<AppState> store) {
      final seen = <bool>[];
      store.onChange.listen((_) => seen.add(_waiting(store).on<_Held>()));
      return seen;
    }

    test('when a wait it has asked about starts, and when it ends', () async {
      final store = _store();
      final before = store.state;
      // the first run of the view-model: it asks, and finds nothing
      expect(_waiting(store).on<_Held>(), isFalse);
      final seen = answers(store);

      final gate = Completer<void>();
      final pending = store.dispatchAndWait(_Held(gate));
      await pumpEventQueue();
      expect(seen, [true], reason: 'the first frame of the wait');

      gate.complete();
      await pending;
      await pumpEventQueue();
      expect(seen.last, isFalse, reason: 'and its end');
      expect(seen.length, greaterThanOrEqualTo(2));
      expect(store.state, same(before), reason: 'no state was changed');
    });

    test('also when the action is dispatched with notify: false', () async {
      final store = _store();
      expect(_waiting(store).on<_Held>(), isFalse);
      final seen = answers(store);

      final gate = Completer<void>();
      final pending = store.dispatchAndWait(_Held(gate), notify: false);
      await pumpEventQueue();
      expect(seen, [true]);

      gate.complete();
      await pending;
      await pumpEventQueue();
      expect(seen.last, isFalse);
    });

    test('also when the action fails', () async {
      final store = _store();
      expect(_waiting(store).on<_HeldThenFails>(), isFalse);
      final seen = <bool>[];
      store.onChange.listen(
        (_) => seen.add(_waiting(store).on<_HeldThenFails>()),
      );

      final gate = Completer<void>();
      final pending = store.dispatchAndWait(_HeldThenFails(gate));
      await pumpEventQueue();
      expect(seen, [true]);

      gate.complete();
      final status = await pending;
      expect(status.originalError, isNotNull, reason: 'it did fail');
      await pumpEventQueue();
      expect(seen.last, isFalse);
    });

    test('a wait nobody asked about tells nobody when it starts', () async {
      // The rule "every rebuild is decided", kept: an action no screen
      // draws makes no view-model run. (Its end is an event when it was
      // dispatched with `notify: true`, as for any action.)
      final store = _store();
      var events = 0;
      store.onChange.listen((_) => events++);

      final gate = Completer<void>();
      final pending = store.dispatchAndWait(_Other(gate), notify: false);
      await pumpEventQueue();
      expect(events, 0);

      gate.complete();
      await pending;
      await pumpEventQueue();
      expect(events, 0);
    });

    test('a view-model that asks behind a condition misses nothing', () async {
      // `a || b` does not ask about `b` while `a` is true, so the store has
      // no record of `b` and does not tell when `b` starts. Nothing is
      // missed: the answer could not have changed. When `a` ends the store
      // tells (it was asked about `a`), the view-model runs, asks about `b`
      // and finds it.
      final store = _store();
      bool vm() => _waiting(store).on<_Held>() || _waiting(store).on<_Other>();
      expect(vm(), isFalse); // asks about both: both false
      final seen = <bool>[];
      store.onChange.listen((_) => seen.add(vm()));

      final a = Completer<void>();
      final first = store.dispatchAndWait(_Held(a));
      await pumpEventQueue();
      expect(seen, [true]);

      final b = Completer<void>();
      final second = store.dispatchAndWait(_Other(b));
      a.complete();
      await first;
      await pumpEventQueue();
      expect(seen.last, isTrue, reason: 'the second is still in flight');

      b.complete();
      await second;
      await pumpEventQueue();
      expect(seen.last, isFalse);
    });

    test('a view-model whose first run is behind a condition', () async {
      // The harder half: `b` was never asked about before it starts,
      // because `a` was already true on the very first run.
      final store = _store();
      final a = Completer<void>();
      final first = store.dispatchAndWait(_Held(a));
      bool vm() => _waiting(store).on<_Held>() || _waiting(store).on<_Other>();
      expect(vm(), isTrue); // asks about `a` only
      final seen = <bool>[];
      store.onChange.listen((_) => seen.add(vm()));

      final b = Completer<void>();
      final second = store.dispatchAndWait(_Other(b));
      await pumpEventQueue();
      a.complete();
      await first;
      await pumpEventQueue();
      expect(seen.last, isTrue, reason: 'still busy: the second runs');

      b.complete();
      await second;
      await pumpEventQueue();
      expect(seen.last, isFalse, reason: 'and told when it ends');
    });
  });
}
