import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/session/actions/set_token_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

void main() {
  Future<void> fill(
    Store<AppState> s, {
    String gateway = 'http://127.0.0.1:8445',
  }) async {
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
  }

  group('LogInAction', () {
    test(
      'logs in, keeps the session and writes the subject as the token',
      () async {
        final login = FakeLogin();
        final s = fakeStore(login: login);
        await fill(s);

        final status = await s.dispatchAndWait(LogInAction());

        expect(status.isCompletedOk, isTrue);
        expect(login.gateways, [Uri.parse('http://127.0.0.1:8445')]);
        expect(login.user, 'admin');
        expect(login.password, 'wyrm-demo-1');
        expect(s.state.session.token, 'user:admin');
        expect(depsOf(s).rawSession, same(login.session));
      },
    );

    test('clears the password and keeps the gateway and the user', () async {
      final s = fakeStore();
      await fill(s);

      await s.dispatchAndWait(LogInAction());

      expect(s.state.login.password, isNull);
      expect(s.state.login.user, 'admin');
      expect(s.state.login.gateway, 'http://127.0.0.1:8445');
    });

    test('passes every gateway of a standby pair, in order', () async {
      final login = FakeLogin();
      final s = fakeStore(login: login);
      await fill(s, gateway: 'http://a:8445, b:8445');

      await s.dispatchAndWait(LogInAction());

      expect(login.gateways, [
        Uri.parse('http://a:8445'),
        Uri.parse('http://b:8445'),
      ]);
    });

    test('a refused password is a user error, and no session starts', () async {
      final s = fakeStore(
        login: FakeLogin(
          error: WyrmException.of(Status.permissionDenied, 'bad credentials'),
        ),
      );
      await fill(s);

      final status = await s.dispatchAndWait(LogInAction());

      expect(status.originalError, isA<UserException>());
      expect(
        (status.originalError! as UserException).reason,
        'bad credentials',
        reason: "the gateway's own message is shown",
      );
      expect(s.state.session.token, isNull);
      expect(depsOf(s).session, isNull);
    });

    test('an unreachable gateway is a user error', () async {
      final s = fakeStore(login: FakeLogin(error: const SocketExceptionLike()));
      await fill(s);

      final status = await s.dispatchAndWait(LogInAction());

      expect(status.originalError, isA<UserException>());
      expect(s.state.session.token, isNull);
    });

    test('an empty gateway field makes no call and no dialog: the form '
        'says it under the field', () async {
      final login = FakeLogin();
      final s = fakeStore(login: login);
      await fill(s, gateway: ' , ');

      final status = await s.dispatchAndWait(LogInAction());

      expect(status.originalError, isNull);
      expect(login.gateways, isNull);
      expect(s.state.session.token, isNull);
      expect(s.state.problems.items, isEmpty);
    });
  });

  group('parseGateways', () {
    test('adds http:// and drops what is not a URL', () {
      expect(parseGateways('127.0.0.1:8445'), [
        Uri.parse('http://127.0.0.1:8445'),
      ]);
      expect(parseGateways('https://g.example:8445'), [
        Uri.parse('https://g.example:8445'),
      ]);
      expect(parseGateways('ftp://x, '), isEmpty);
      expect(parseGateways(''), isEmpty);
    });
  });

  group('the session flag', () {
    test('SetTokenAction accepts null — that is what a log-out is', () async {
      final s = fakeStore(
        initial: AppState.initial().copyWith.session(token: 'tok'),
      );

      await s.dispatchAndWait(SetTokenAction(value: null));

      expect(s.state.session.token, isNull);
    });

    test('the guard sees the flip in both directions', () async {
      final s = fakeStore();
      expect(SelectSession(s.state).isAvailable, isFalse);

      await s.dispatchAndWait(SetTokenAction(value: 'tok'));
      expect(SelectSession(s.state).isAvailable, isTrue);

      await s.dispatchAndWait(SetTokenAction(value: null));
      expect(SelectSession(s.state).isAvailable, isFalse);
    });
  });

  group('the language can be changed', () {
    test('SetLanguageAction writes the locale code', () async {
      final s = fakeStore();
      expect(s.state.language.locale, 'en');

      await s.dispatchAndWait(SetLanguageAction('uk'));

      expect(SelectLanguage(s.state).locale, 'uk');
    });
  });
}

/// Any non-gateway failure (a refused TCP connection, a DNS error).
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
