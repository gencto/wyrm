import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds an [AppState] and nothing else — which is the entire contract
/// [Selectors] asks for.
///
/// That one-member requirement is the facade's best property, and this class is
/// the proof: a reducer, a connector's `_Factory` and a test all satisfy it the
/// same way, so the selectors are exercised through exactly the surface
/// production code uses.
class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}

void main() {
  group('the facade reads through to its slice', () {
    test('every selector answers from AppState.initial()', () {
      final r = _Reader(AppState.initial());

      expect(r.connectivity.isConnected, isTrue);
      expect(r.login.gateway, isNull);
      expect(r.login.user, isNull);
      expect(r.login.password, isNull);
      expect(r.session.token, isNull);
      expect(r.theme.mode, ThemeMode.light);
      expect(r.language.locale, 'en');
    });

    test('a written slice is what the selector returns', () {
      final r = _Reader(
        AppState.initial().copyWith
            .login(user: 'admin', password: 'secret')
            .copyWith
            .session(token: 'tok'),
      );

      expect(r.login.user, 'admin');
      expect(r.login.password, 'secret');
      expect(r.session.token, 'tok');
    });
  });

  group('SelectSession.isAvailable', () {
    test('is false without a token and true with one', () {
      expect(_Reader(AppState.initial()).session.isAvailable, isFalse);
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: 'tok'),
        ).session.isAvailable,
        isTrue,
      );
    });

    test('an empty string is a token — the check is null, not blank', () {
      // Pinning the rule rather than endorsing it: the router gates the whole
      // app on this (`_AuthGuard`), so if it should reject `''` the change
      // belongs here, where one test names it.
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: ''),
        ).session.isAvailable,
        isTrue,
      );
    });
  });

  group('SelectComposites.isBusy', () {
    test('is false when nothing is in flight', () {
      expect(_Reader(AppState.initial()).isBusy, isFalse);
    });

    test('every waiting action raises it', () {
      // Named one by one rather than folded, because *which* actions count is
      // the claim. The barrier read `login.isWaiting || registration.isWaiting`
      // and the last two are the ones that were missing from it — they mix in
      // `WaitingAction` and have an `isWaiting` getter, and still showed the
      // user nothing for the two seconds they ran.
      for (final action in <ReduxAction<AppState>>[
        LogInAction(),
      ]) {
        final r = _Reader(
          AppState.initial().copyWith(wait: Wait.empty.add(flag: action)),
        );
        expect(
          r.isBusy,
          isTrue,
          reason: '${action.runtimeType} should raise the barrier',
        );
      }
    });

    test('an action written later raises it with no edit here', () {
      // The property a list of slices cannot have: membership is the mixin, so
      // nothing has to be told about a new action.
      final r = _Reader(
        AppState.initial().copyWith(wait: Wait.empty.add(flag: _LaterAction())),
      );

      expect(r.isBusy, isTrue);
    });

    test('a waiting action that is not blocking leaves the screen', () {
      // The reason this is keyed on `BlockingAction`. Every async action that
      // wants an indicator mixes in `WaitingAction`, because that is what puts
      // it in `Wait` — so keying on *that* would blank the app for the first
      // background refresh anyone adds. This is the case both earlier
      // predicates got wrong.
      final r = _Reader(
        AppState.initial().copyWith(
          wait: Wait.empty.add(flag: _BackgroundAction()),
        ),
      );

      expect(r.isBusy, isFalse);
    });

    test('a flag that is not an action at all does not either', () {
      // `Wait` takes any `Object?` as a flag, so `isWaitingAny` was true for
      // things that are not operations the user is waiting on.
      final r = _Reader(
        AppState.initial().copyWith(wait: Wait.empty.add(flag: 'some-flag')),
      );

      expect(r.isBusy, isFalse);
    });
  });
}

/// Stands in for an action written after this test that opts into the barrier —
/// the case the hand-listed disjunction could not cover.
class _LaterAction extends ReduxAction<AppState>
    with WaitingAction, BlockingAction {
  @override
  AppState? reduce() => null;
}

/// Waits so it can drive its own indicator, and does not ask to be covered —
/// a background refresh, a poll, a paginating load.
class _BackgroundAction extends ReduxAction<AppState> with WaitingAction {
  @override
  AppState? reduce() => null;
}
