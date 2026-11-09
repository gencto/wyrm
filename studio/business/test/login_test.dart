import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/open_tree_action.dart';
import 'package:business/redux/login/actions/probe_gateway_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_remember_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/login_failure.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// The log-in page's states (docs/design/specs/login.md §5, §6): steps,
/// failures, probes, recent gateways and Remember.
void main() {
  Future<void> fill(
    Store<AppState> s, {
    String gateway = 'http://a:8445',
  }) async {
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
  }

  group('LogInAction', () {
    test('walks the three steps and remembers the gateway', () async {
      final login = FakeLogin();
      final s = fakeStore(login: login);
      final steps = <int>[];
      s.onChange.listen((st) {
        if (steps.isEmpty || steps.last != st.login.step) {
          steps.add(st.login.step);
        }
      });
      await fill(s);

      final status = await s.dispatchAndWait(LogInAction());

      expect(status.isCompletedOk, isTrue);
      expect(steps, containsAllInOrder([0, 1, 2]));
      expect(s.state.login.step, 0, reason: 'back at rest');
      expect(login.probed, [Uri.parse('http://a:8445')]);
      expect(s.state.login.failure, isNull);
      expect(s.state.login.recent, ['http://a:8445']);
      expect(s.state.login.probes['http://a:8445'], 12);
    });

    test(
      'no answer from any gateway is unreachable, before any login',
      () async {
        final login = FakeLogin(
          answer: const GatewayProbe.noAnswer('connection refused after 5 s'),
        );
        final s = fakeStore(login: login);
        await fill(s, gateway: 'http://a:8445, http://b:8445');

        final status = await s.dispatchAndWait(LogInAction());

        final error = status.originalError! as UserException;
        expect(error.ifOpenDialog, isFalse, reason: 'the page shows it inline');
        expect(login.gateways, isNull, reason: 'no login was tried');
        expect(login.probed, hasLength(2), reason: 'the standby is tried too');
        expect(s.state.login.failure, LoginFailure.unreachable);
        expect(s.state.login.reason, 'connection refused after 5 s');
        expect(s.state.login.probes['http://b:8445'], -1);
      },
    );

    test('a refused password is wrong, shown inline', () async {
      final s = fakeStore(
        login: FakeLogin(
          error: WyrmException.of(Status.permissionDenied, 'bad credentials'),
        ),
      );
      await fill(s);

      final status = await s.dispatchAndWait(LogInAction());

      expect((status.originalError! as UserException).ifOpenDialog, isFalse);
      expect(s.state.login.failure, LoginFailure.wrong);
      expect(s.state.login.step, 1, reason: 'it failed while checking');
    });

    test('a new attempt clears the last failure', () async {
      final s = fakeStore(
        initial: AppState.initial().copyWith.login(
          failure: LoginFailure.wrong,
        ),
      );
      await fill(s);

      await s.dispatchAndWait(LogInAction());

      expect(s.state.login.failure, isNull);
    });
  });

  group('remembered', () {
    test('puts the gateway first, once, and keeps five', () {
      final recent = ['a', 'b', 'c', 'd', 'e'].lock;

      expect(remembered(recent, 'c'), ['c', 'a', 'b', 'd', 'e']);
      expect(remembered(recent, ' f '), ['f', 'a', 'b', 'c', 'd']);
    });
  });

  group('ProbeGatewayAction', () {
    test('keeps the time of each gateway, -1 for no answer', () async {
      final s = fakeStore(login: FakeLogin());
      await s.dispatchAndWait(ProbeGatewayAction('http://a:8445, b:8446'));

      expect(s.state.login.probes.unlock, {
        'http://a:8445': 12,
        'http://b:8446': 12,
      });

      final down = fakeStore(
        login: FakeLogin(answer: const GatewayProbe.noAnswer('timed out')),
      );
      await down.dispatchAndWait(ProbeGatewayAction('http://a:8445'));

      expect(down.state.login.probes['http://a:8445'], -1);
    });

    test(
      'probes the field when given nothing, and nothing when it is empty',
      () async {
        final login = FakeLogin();
        final s = fakeStore(login: login);

        await s.dispatchAndWait(ProbeGatewayAction());
        expect(login.probed, isEmpty);

        await s.dispatchAndWait(SetGatewayAction('http://a:8445'));
        await s.dispatchAndWait(ProbeGatewayAction());
        expect(login.probed, [Uri.parse('http://a:8445')]);
      },
    );
  });

  group('OpenTreeAction', () {
    late FakeLogin login;
    late FakeWyrmApi api;
    late Store<AppState> s;
    const root = 'wy/central';

    setUp(() async {
      login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await fill(s);
      await s.dispatchAndWait(LogInAction());
      // A site with one link, one flow, two block types and nothing above.
      api
        ..children_['$root/dataflows'] = [Child('f1', NodeMeta())]
        ..invokes['$root/dataflows/f1 ▸ history'] = []
        ..invokes['$root/dataflows ▸ node_types'] = [
          Value.from([
            {'type': 'add', 'category': 'math'},
            {'type': 'const', 'category': 'input'},
          ]),
        ]
        ..children_['$root/sys/links'] = [Child('modbus', NodeMeta())]
        ..metas['$root/sys/links/modbus'] = NodeMeta()
        ..initial['$root/sys/version'] = [
          const ValSample('$root/sys/version', Sample(VStr('0.9.4'), t: 0)),
        ]
        ..children_['$root/downstream'] = []
        ..children_['$root/sys/upstream'] = [];
    });

    /// Answers the first list of each tree section once it is asked for.
    Future<void> answerLists() async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final open = [
          for (final sec in OpenTreeAction.sections)
            if (api.lists['$root/$sec'] case final c? when c.hasListener) c,
        ];
        if (open.length == OpenTreeAction.sections.length) {
          for (final c in open) {
            c.add(const ListRefreshed([]));
          }
          return;
        }
      }
    }

    /// Every error the store queued for a dialog.
    List<UserException> dialogs() => [
      for (
        var e = s.getAndRemoveFirstError();
        e != null;
        e = s.getAndRemoveFirstError()
      )
        if (e.ifOpenDialog) e,
    ];

    test('reads the tree, flows, blocks, links and sites in turn', () async {
      final progress = <int>[];
      s.onChange.listen((st) {
        if (progress.isEmpty || progress.last != st.login.preload) {
          progress.add(st.login.preload);
        }
      });

      unawaited(answerLists());
      await s.dispatchAndWait(
        OpenTreeAction(atLeast: Duration.zero),
      );

      int first(String op, String key, [String? action]) =>
          api.calls.indexWhere(
            (c) => c.op == op && c.key == key && c.action == action,
          );
      final order = [
        first('list', '$root/downstream'),
        first('list', '$root/dataflows'),
        first('list', '$root/storage'),
        first('children', '$root/dataflows'),
        first('invoke', '$root/dataflows', 'node_types'),
        first('children', '$root/sys/links'),
        first('children', '$root/sys/upstream'),
      ];
      expect(order, isNot(contains(-1)), reason: '$order');
      expect([...order]..sort(), order, reason: 'one after the other');
      await Future<void>.delayed(Duration.zero);
      expect(progress, containsAllInOrder([0, 1, 2, 3, 4, 5]));
      expect(s.state.login.preloadLate, isEmpty);
      expect(
        s.state.nodes.expanded,
        {'$root/downstream'},
        reason: 'dataflows and storage are listed, not opened',
      );
      expect(s.state.flows.view, ['f1']);
      expect(s.state.flows.blockTypes.map((t) => t.type), ['const', 'add']);
      expect(s.state.links.view, ['modbus']);
      expect(s.state.site.choices.map((c) => c.site), ['central']);
      expect(dialogs(), isEmpty);

      // The editor opens from the cache: no second catalogue read.
      api.calls.clear();
      await s.dispatchAndWait(LoadFlowAction('f2', isNew: true));
      expect(
        api.calls.where((c) => c.action == 'node_types'),
        isEmpty,
      );
      expect(s.state.flowEditor.types, hasLength(2));
    });

    test('a slow broker does not hold the welcome past its cap', () async {
      // The tree never answers and the catalogue takes 10 s.
      api.delays['$root/dataflows ▸ node_types'] = const Duration(seconds: 10);
      final watch = Stopwatch()..start();

      await s.dispatchAndWait(
        OpenTreeAction(
          atLeast: Duration.zero,
          atMost: const Duration(milliseconds: 400),
          perStep: const Duration(milliseconds: 250),
        ),
      );

      expect(watch.elapsedMilliseconds, lessThan(700));
      expect(s.state.login.preload, OpenTreeAction.steps);
      expect(s.state.login.preloadLate, containsAll([0, 1]));
      // What the deadline reached before it started still starts.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        api.calls.map((c) => c.key),
        containsAll(['$root/sys/links', '$root/sys/upstream']),
      );
      expect(dialogs(), isEmpty);
    });

    test('waits at least its minimum, so the welcome does not flash', () async {
      unawaited(answerLists());
      final watch = Stopwatch()..start();

      await s.dispatchAndWait(
        OpenTreeAction(atLeast: const Duration(milliseconds: 1500)),
      );

      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(1500));
    });

    test('a refused read opens no dialog; a screen read still does', () async {
      unawaited(answerLists());
      api
        ..errors['$root/sys/links'] = WyrmException.of(
          Status.permissionDenied,
          'no read on sys',
        )
        ..errors['$root/dataflows ▸ node_types'] = WyrmException.of(
          Status.permissionDenied,
          'no read on dataflows',
        );

      final status = await s.dispatchAndWait(
        OpenTreeAction(atLeast: Duration.zero),
      );

      expect(status.isCompletedOk, isTrue);
      expect(s.state.login.preloadLate, containsAll([2, 3]));
      expect(dialogs(), isEmpty);

      await s.dispatchAndWait(RetrieveLinksAction());
      expect(dialogs(), hasLength(1), reason: 'quiet is per dispatch');
    });
  });

  group('the persistor and Remember', () {
    test('keeps the recent gateways and the choice', () async {
      final storage = InMemoryKeyValueStorage();
      final persistor = AppPersistor(storage);
      final state = AppState.initial().copyWith.login(
        gateway: 'http://a:8445',
        user: 'admin',
        recent: ['http://a:8445', 'http://b:8445, http://c:8445'].lock,
      );

      await persistor.persistDifference(newState: state);
      final back = await persistor.readState();

      expect(back?.login.recent, state.login.recent);
      expect(back?.login.remember, isTrue);
      expect(back?.login.user, 'admin');
    });

    test('Remember off forgets the gateway, the user and the list', () async {
      final storage = InMemoryKeyValueStorage();
      final persistor = AppPersistor(storage);
      final on = AppState.initial().copyWith.login(
        gateway: 'http://a:8445',
        user: 'admin',
        recent: ['http://a:8445'].lock,
      );
      await persistor.persistDifference(newState: on);
      final s = fakeStore(initial: on);
      await s.dispatchAndWait(SetRememberAction(false));

      await persistor.persistDifference(
        newState: s.state,
        lastPersistedState: on,
      );
      final back = await persistor.readState();

      expect(back?.login.remember, isFalse);
      expect(back?.login.gateway, isNull);
      expect(back?.login.user, isNull);
      expect(back?.login.recent, isEmpty);
      expect(back?.login.password, isNull);
    });
  });
}
