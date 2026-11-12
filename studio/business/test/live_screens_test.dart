import 'package:async_redux/async_redux.dart';
import 'package:business/redux/access/actions/poll_access_action.dart';
import 'package:business/redux/access/actions/retrieve_access_action.dart';
import 'package:business/redux/access/actions/set_selected_action.dart';
import 'package:business/redux/access/actions/set_shown_action.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/flows/actions/follow_flows_action.dart';
import 'package:business/redux/flows/actions/set_selected_flow_action.dart';
import 'package:business/redux/historian/actions/follow_history_action.dart';
import 'package:business/redux/historian/actions/pick_point_action.dart';
import 'package:business/redux/historian/actions/retrieve_series_action.dart';
import 'package:business/redux/historian/actions/set_range_action.dart';
import 'package:business/redux/historian/actions/set_selected_action.dart'
    as history;
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// History, Flows and Access keep their data fresh while their tab is shown
/// (owner report 2026-11-12): live lists and values for the first two, a
/// read every 10 s for Access; nothing stays open after a hide or for the
/// site left behind.
void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  /// Lets list events and one batch of live values (200 ms) through.
  Future<void> settle([int ms = 0]) =>
      Future<void>.delayed(Duration(milliseconds: ms));
  Future<void> batch() => settle(260);

  Set<String> listed() => depsOf(s).liveLists.listed;
  Set<String> subscribed() => depsOf(s).liveValues.watched;
  int calls(String op, String key, [String? action]) => api.calls
      .where((c) => c.op == op && c.key == key && c.action == action)
      .length;
  int now() => DateTime.now().toUtc().microsecondsSinceEpoch;

  Child node(String name, {String? display}) =>
      Child(name, NodeMeta(display: display));

  group('History', () {
    const base = 'wy/central/sys/history';
    const a = 'wy/central/downstream/m/a';
    const b = 'wy/central/downstream/m/b';

    Future<void> show() async {
      s.dispatchSync(FollowHistoryAction(show: true));
      await settle();
      api.lists[base]!.add(ListRefreshed([node('ahu'), node('vav')]));
      await settle();
      api.lists['$base/ahu']!.add(
        ListRefreshed([node('w0', display: a), node('w1', display: b)]),
      );
      await settle();
    }

    setUp(() {
      api
        ..children_['$base/vav'] = [node('w9', display: a)]
        ..children_['$base/boiler'] = [
          node('w1', display: a),
          node('w2', display: b),
        ]
        ..histories[a] = [
          // An hour and half an hour ago: buckets before the current one.
          HistRow(now() - 3600000000, const VFloat(1), Quality.good),
          HistRow(now() - 1800000000, const VFloat(2), Quality.good),
        ];
    });

    test('groups and watches come from live lists', () async {
      await show();
      final h = s.state.historian;
      expect(h.groups.map((g) => g.name), ['ahu', 'vav']);
      expect(h.selected, 'ahu');
      expect(h.groups.first.keys, [a, b]);
      // The selected group is listed live; the other is read once.
      expect(listed(), {base, '$base/ahu'});
      expect(calls('children', '$base/vav'), 1);
      expect(h.groups.last.keys, [a]);
      expect(calls('children', '$base/ahu'), 0);
    });

    test('a group added elsewhere appears, a removed one goes', () async {
      await show();
      api.lists[base]!.add(ChildAdded(node('boiler')));
      await settle(20);
      expect(s.state.historian.groups.map((g) => g.name), [
        'ahu',
        'vav',
        'boiler',
      ]);
      expect(s.state.historian.groups.last.keys, [a, b]);

      api.lists[base]!.add(const ChildRemoved('vav'));
      await settle();
      expect(s.state.historian.groups.map((g) => g.name), ['ahu', 'boiler']);

      // The selected group removed: the next one is shown and listed.
      api.lists[base]!.add(const ChildRemoved('ahu'));
      await settle();
      expect(s.state.historian.selected, 'boiler');
      expect(listed(), {base, '$base/boiler'});
    });

    test('a watch added or stopped elsewhere changes the points', () async {
      await show();
      s.dispatchSync(PickPointAction(b));
      api.lists['$base/ahu']!.add(ChildAdded(node('w2', display: 'k')));
      await settle();
      expect(s.state.historian.groups.first.keys, [a, b, 'k']);
      api.lists['$base/ahu']!.add(const ChildRemoved('w1'));
      await settle();
      expect(s.state.historian.groups.first.keys, [a, 'k']);
      // The picked point is no longer recorded: it leaves the trend.
      expect(s.state.historian.points, isEmpty);
      expect(subscribed(), isNot(contains(b)));
    });

    test('a new sample of a picked point extends its trend', () async {
      await show();
      s.dispatchSync(PickPointAction(a));
      await s.dispatchAndWait(RetrieveSeriesAction());
      expect(s.state.historian.series[a]!.length, 2);
      expect(subscribed(), contains(a));

      // The stored value, older than the read: nothing new.
      api.subs[a]!.add(
        ValSample(a, Sample(const VFloat(2), t: now() - 1800000000)),
      );
      await batch();
      expect(s.state.historian.series[a]!.length, 2);

      api.subs[a]!.add(ValSample(a, Sample(const VFloat(7), t: now())));
      await batch();
      final series = s.state.historian.series[a]!;
      expect(series.length, 3);
      expect(series.last.value, 7);

      // A sample in the same bucket (24 h / 300 ≈ 4.8 min) takes its place.
      api.subs[a]!.add(ValSample(a, Sample(const VBool(true), t: now())));
      await batch();
      expect(s.state.historian.series[a]!.length, 3);
      expect(s.state.historian.series[a]!.last.value, 1);

      // Points older than the range drop off (1 h: the first one).
      s.dispatchSync(SetRangeAction('1h'));
      api.subs[a]!.add(ValSample(a, Sample(const VFloat(8), t: now())));
      await batch();
      expect(s.state.historian.series[a]!.map((p) => p.value), [2, 8]);

      // Unpicked: the point's subscription closes.
      s.dispatchSync(PickPointAction(a));
      expect(subscribed(), isNot(contains(a)));
    });

    test('the historian values and group settings are live', () async {
      await show();
      api.subs['$base/*']!.add(
        ValSample('$base/rows_written', Sample(const VInt(42), t: now())),
      );
      api.subs['$base/*/*']!.add(
        ValSample(
          '$base/ahu/logging_type',
          Sample(const VStr('Point Change'), t: now()),
        ),
      );
      await batch();
      final h = SelectHistorian(s.state);
      expect(h.shownStats['rows_written'], '42');
      expect(h.shownGroups.first.loggingType, 'Point Change');
    });

    test('another group moves the watch list; hide closes all', () async {
      await show();
      s
        ..dispatchSync(PickPointAction(a))
        ..dispatchSync(history.SetSelectedAction('vav'));
      expect(listed(), {base, '$base/vav'});
      expect(subscribed(), isNot(contains(a)));

      s.dispatchSync(FollowHistoryAction(show: false));
      expect(listed(), isEmpty);
      expect(subscribed(), isEmpty);
      expect(s.state.live.lists, isEmpty);
      expect(s.state.live.watched, isEmpty);
      expect(s.state.historian.follow, isNull);

      // Hidden: a list event of before changes nothing.
      api.lists[base]!.add(ChildAdded(node('late')));
      await settle();
      expect(s.state.historian.groups.map((g) => g.name), ['ahu', 'vav']);
    });

    test('a refused list is a quiet problem; one the user may not read is '
        'just empty', () async {
      await show();
      api.lists['$base/ahu']!.addError(
        WyrmException.of(Status.permissionDenied, ''),
      );
      await settle();
      expect(s.state.historian.groups.first.keys, isEmpty);
      expect(s.state.problems.items, isEmpty);

      api.lists[base]!.addError(WyrmException.of(Status.notFound, 'gone'));
      await settle();
      expect(s.state.historian.groups, isEmpty);
      final p = s.state.problems.items.single;
      expect(p.key, base);
      expect(p.quiet, isTrue);
    });

    test('a site switch closes the old site and opens the new', () async {
      await show();
      s.dispatchSync(ViewSiteAction('edge'));
      await settle();
      const edge = 'wy/edge/sys/history';
      expect(listed(), {edge});
      expect(subscribed(), {'$edge/*', '$edge/*/*'});
      expect(s.state.historian.groups, isEmpty);
      api.lists[edge]!.add(ListRefreshed([node('pumps')]));
      await settle();
      expect(s.state.historian.groups.map((g) => g.name), ['pumps']);
      expect(listed(), {edge, '$edge/pumps'});
    });
  });

  group('Flows', () {
    const df = 'wy/central/dataflows';
    final def = Value.from({
      'id': 'f',
      'nodes': {
        'in': {'type': 'subscribe', 'key': 'downstream/m/a'},
        'out': {'type': 'publish', 'key': 'storage/a'},
      },
      'edges': [
        ['in.out', 'out.in'],
      ],
    });

    Future<void> show() async {
      s.dispatchSync(FollowFlowsAction(show: true));
      await settle();
    }

    setUp(() {
      for (final id in ['f1', 'f2']) {
        api.invokes['$df/$id ▸ history'] = [
          VArray([def]),
        ];
      }
    });

    ValSample val(String id, int version, {int state = 0}) => ValSample(
      '$df/$id',
      Sample(
        Value.from({'version': version, 'state': state, 'deployed_by': 'u'}),
        t: now(),
      ),
    );

    test('flows come from the live list and are read once', () async {
      await show();
      expect(listed(), {df});
      expect(subscribed(), {'$df/*'});
      api.subs['$df/*']!.add(val('f1', 1));
      await batch();
      api.lists[df]!.add(ListRefreshed([node('f1')]));
      await settle(20);
      final f = s.state.flows.table['f1']!;
      expect(f.blocks, 2);
      expect(f.version, 1);
      expect(calls('invoke', '$df/f1', 'history'), 1);
      expect(SelectFlows(s.state).shownTable['f1']!.running, isTrue);
    });

    test('a new flow appears, a removed one goes; a new version is read '
        'again, the same one is not', () async {
      await show();
      api.subs['$df/*']!.add(val('f1', 1));
      await batch();
      api.lists[df]!.add(ListRefreshed([node('f1')]));
      await settle(20);
      s.dispatchSync(SetSelectedFlowAction('f1'));

      api.lists[df]!.add(ChildAdded(node('f2')));
      await settle(20);
      expect(s.state.flows.view, ['f1', 'f2']);
      expect(calls('invoke', '$df/f2', 'history'), 1);

      // The same version again (a state change): no read.
      api.subs['$df/*']!.add(val('f1', 1, state: 2));
      await batch();
      expect(calls('invoke', '$df/f1', 'history'), 1);
      expect(SelectFlows(s.state).shownTable['f1']!.problem, 'error');

      // Deployed again elsewhere: its definition is read again.
      api.subs['$df/*']!.add(val('f1', 2));
      await batch();
      await settle(20);
      expect(calls('invoke', '$df/f1', 'history'), 2);
      expect(s.state.flows.table['f1']!.version, 2);

      api.lists[df]!.add(const ChildRemoved('f1'));
      await settle();
      expect(s.state.flows.view, ['f2']);
      expect(s.state.flows.selectedFlow, isNull);
    });

    test('hide and a site switch close the subscriptions', () async {
      await show();
      s.dispatchSync(ViewSiteAction('edge'));
      expect(listed(), {'wy/edge/dataflows'});
      expect(subscribed(), {'wy/edge/dataflows/*'});
      s.dispatchSync(FollowFlowsAction(show: false));
      expect(listed(), isEmpty);
      expect(subscribed(), isEmpty);
      expect(s.state.flows.follow, isNull);
    });
  });

  group('Access', () {
    test('a poll reads again while shown, keeps the selection, and stops '
        'after hide', () async {
      login.session.userTable['ann'] = const GatewayUser('ann', ['viewer']);
      s.dispatchSync(SetShownAction(true));
      await s.dispatchAndWait(RetrieveAccessAction());
      s.dispatchSync(SetSelectedAction('ann'));
      expect(s.state.access.users.map((u) => u.name), ['ann']);

      // Made elsewhere: the next poll shows it.
      login.session.userTable['bob'] = const GatewayUser('bob', ['operator']);
      await s.dispatchAndWait(PollAccessAction());
      expect(s.state.access.users.map((u) => u.name), ['ann', 'bob']);
      expect(s.state.access.selected, 'ann');

      s.dispatchSync(SetShownAction(false));
      login.session.userTable['cy'] = const GatewayUser('cy', ['viewer']);
      await s.dispatchAndWait(PollAccessAction());
      expect(s.state.access.users.map((u) => u.name), ['ann', 'bob']);
    });

    test('a poll is not in Wait (no sweep bar) and is silent', () {
      expect(PollAccessAction(), isNot(isA<WaitingAction>()));
    });
  });
}
