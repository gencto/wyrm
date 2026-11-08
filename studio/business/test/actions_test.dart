import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/connectivity/actions/set_connectivity_status_action.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/session/actions/set_token_action.dart';
import 'package:business/redux/theme/actions/set_theme_mode_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store with nothing but a state.
///
/// Deliberately **not** `createStore`: that opens a real sembast file through
/// path_provider and takes no parameters to stop it. `Store` needs only
/// `initialState`, and every action here reads neither `deps` nor `env`, so
/// nothing else is required. An action that starts needing a dependency is the
/// signal to inject it — not the signal to boot the app in a test.
Store<AppState> _store([AppState? initial]) =>
    Store<AppState>(initialState: initial ?? AppState.initial());

void main() {
  group('the log-in setters write to the login slice', () {
    test('SetGatewayAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetGatewayAction('http://127.0.0.1:8445'));

      expect(store.state.login.gateway, 'http://127.0.0.1:8445');
    });

    test('SetUserAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetUserAction('admin'));

      expect(store.state.login.user, 'admin');
    });

    test('SetPasswordAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetPasswordAction('secret'));

      expect(store.state.login.password, 'secret');
    });

    test('a null clears the field rather than being ignored', () async {
      // The connectors dispatch on every keystroke, so emptying the input has
      // to reach the store as null. A setter that treated null as "no change"
      // would leave the last typed value behind.
      final store = _store(AppState.initial().copyWith.login(user: 'admin'));
      await store.dispatchAndWait(SetUserAction(null));

      expect(store.state.login.user, isNull);
    });
  });

  group('the single-value setters', () {
    test('SetThemeModeAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetThemeModeAction(ThemeMode.light));

      expect(store.state.theme.mode, ThemeMode.light);
    });

    test('SetLanguageAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetLanguageAction('uk'));

      expect(store.state.language.locale, 'uk');
    });

    test('SetTokenAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetTokenAction(value: 'tok'));

      expect(store.state.session.token, 'tok');
    });

    test('SetConnectivityStatusAction', () async {
      final store = _store();
      await store.dispatchAndWait(SetConnectivityStatusAction(value: false));

      expect(store.state.connectivity.isAvailable, isFalse);
    });
  });

  group('AppState.initial()', () {
    test('starts logged out, online, dark and English', () {
      final state = AppState.initial();

      expect(state.session.token, isNull);
      expect(state.connectivity.isAvailable, isTrue);
      expect(state.theme.mode, ThemeMode.dark);
      expect(state.language.locale, 'en');
    });

    test('is a value — two calls are equal', () {
      // Freezed gives this for free, and the persistor's diff relies on it:
      // `persistDifference` compares slices, so a state that is not a value
      // would write all three keys on every change.
      expect(AppState.initial(), AppState.initial());
    });
  });
}
