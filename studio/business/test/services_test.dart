// The fake streams live as long as each test.
// ignore_for_file: close_sinks

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/set_expanded_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

Future<void> settle([int ms = 250]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeLogin login;

  setUp(() => login = FakeLogin());

  Future<void> logIn(Store<AppState> s) async {
    await s.dispatchAndWait(SetGatewayAction('http://127.0.0.1:8445'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  }

  group('live values', () {
    test('a watched key is subscribed once; samples arrive batched', () async {
      final s = fakeStore(login: login);
      await logIn(s);
      final api = login.session.api;

      s
        ..dispatchSync(WatchKeysAction(['wy/edge/downstream/mock/a']))
        ..dispatchSync(WatchKeysAction(['wy/edge/downstream/mock/a']));
      expect(
        api.calls.where((c) => c.op == 'subscribe').map((c) => c.key),
        ['wy/edge/downstream/mock/a'],
      );

      final sub = api.subs['wy/edge/downstream/mock/a']!;
      for (var i = 0; i < 10; i++) {
        sub.add(
          ValSample(
            'wy/edge/downstream/mock/a',
            Sample(VInt(i), t: 1794108760000000 + i),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(s.state.live.values, isEmpty, reason: 'still in the buffer');

      await settle();
      expect(s.state.live.values['wy/edge/downstream/mock/a']?.value, 9);
    });

    test('unwatching closes the key and forgets its value', () async {
      final s = fakeStore(login: login);
      await logIn(s);
      s.dispatchSync(WatchKeysAction(['wy/e/sys/links/*/state']));
      login.session.api.subs['wy/e/sys/links/*/state']!.add(
        const ValSample('wy/e/sys/links/m/state', Sample(VInt(2), t: 1)),
      );
      await settle();
      expect(s.state.live.values.keys, ['wy/e/sys/links/m/state']);

      s.dispatchSync(UnwatchKeysAction(['wy/e/sys/links/*/state']));

      expect(s.state.live.watched, isEmpty);
      expect(s.state.live.values, isEmpty, reason: 'values under a pattern go');
    });

    test('keys watched before the login are opened by it', () async {
      final s = fakeStore(login: login)
        ..dispatchSync(WatchKeysAction(['wy/c/sys/uptime']));

      await logIn(s);

      expect(
        login.session.api.calls.map((c) => '${c.op} ${c.key}'),
        contains('subscribe wy/c/sys/uptime'),
      );
    });
  });

  group('tree watch', () {
    test('an expanded node is listed live: refresh, add, remove', () async {
      final s = fakeStore(login: login);
      await logIn(s);
      final api = login.session.api;

      depsOf(s).treeWatch.open('wy/edge/downstream');
      final list = api.lists['wy/edge/downstream']!;
      Child c(String n) => Child(n, NodeMeta(hasNodes: true));
      list.add(ListRefreshed([c('modbus'), c('mock')]));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.nodes.view, [
        'wy/edge/downstream/modbus',
        'wy/edge/downstream/mock',
      ]);

      list
        ..add(ChildAdded(c('snmp')))
        ..add(const ChildRemoved('mock'));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.nodes.view, [
        'wy/edge/downstream/modbus',
        'wy/edge/downstream/snmp',
      ]);
      expect(
        s.state.nodes.table['wy/edge/downstream/snmp']?.hasChildren,
        isTrue,
      );
    });

    test(
      'a second refresh drops children that left, and their branches',
      () async {
        final s = fakeStore(login: login);
        await logIn(s);
        final api = login.session.api;
        final tw = depsOf(s).treeWatch..open('wy/e/downstream');
        Child c(String n) => Child(n, NodeMeta());
        api.lists['wy/e/downstream']!.add(ListRefreshed([c('a'), c('b')]));
        await Future<void>.delayed(Duration.zero);
        tw.open('wy/e/downstream/a');
        api.lists['wy/e/downstream/a']!.add(ListRefreshed([c('x')]));
        await Future<void>.delayed(Duration.zero);
        expect(s.state.nodes.table.keys, contains('wy/e/downstream/a/x'));

        api.lists['wy/e/downstream']!.add(ListRefreshed([c('b')]));
        await Future<void>.delayed(Duration.zero);

        expect(s.state.nodes.table.keys, ['wy/e/downstream/b']);
      },
    );

    test('expanded nodes are listed again after a new login', () async {
      final s = fakeStore(login: login);
      await s.dispatchAndWait(
        SetExpandedAction(ISet(const ['wy/c/downstream'])),
      );

      await logIn(s);

      expect(login.session.api.calls.map((c) => '${c.op} ${c.key}'), [
        'list wy/c/downstream',
      ]);
    });
  });

  group('connection', () {
    test(
      'a lost socket clears site.connected; back again reruns the reads',
      () async {
        final s = fakeStore(login: login);
        await logIn(s);
        var reloads = 0;
        depsOf(s).reloads.add((_) => reloads++);
        final conn = login.session.connected..add(true);
        await Future<void>.delayed(Duration.zero);
        expect(s.state.site.connected, isTrue);
        expect(reloads, 0, reason: 'already connected at login');

        conn.add(false);
        await Future<void>.delayed(Duration.zero);
        expect(s.state.site.connected, isFalse);

        conn.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(s.state.site.connected, isTrue);
        expect(reloads, 1);
      },
    );
  });

  group('LogOutAction', () {
    test(
      'closes the session, empties the broker state, keeps the rest',
      () async {
        final s = fakeStore(login: login);
        await logIn(s);
        s.dispatchSync(WatchKeysAction(['wy/c/sys/uptime']));

        await s.dispatchAndWait(LogOutAction());

        expect(login.session.closed, isTrue);
        expect(depsOf(s).session, isNull);
        expect(s.state.session.token, isNull);
        expect(s.state.site.name, isNull);
        expect(s.state.live.watched, isEmpty);
        expect(
          s.state.login.user,
          'admin',
          reason: 'the next login starts here',
        );
        expect(s.state.login.password, isNull);
        expect(depsOf(s).liveValues.watched, isEmpty);
      },
    );
  });
}
