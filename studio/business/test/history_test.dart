import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/pick_point_action.dart';
import 'package:business/redux/historian/actions/retrieve_historian_action.dart';
import 'package:business/redux/historian/actions/retrieve_series_action.dart';
import 'package:business/redux/historian/actions/set_range_action.dart';
import 'package:business/redux/historian/actions/set_selected_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// History reads the groups and their points on open and refresh, and the
/// recorded values only of the points the user picks (owner 2026-11-11).
void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;

  const base = 'wy/central/sys/history';
  const a = 'wy/central/downstream/m/a';
  const b = 'wy/central/downstream/m/b';
  const c = 'wy/central/downstream/m/c';
  const d = 'wy/central/downstream/m/d';

  // The reads of the line, not the buckets' min and max that follow.
  List<String> historyReads() => [
    for (final x in api.calls)
      if (x.op == 'history' &&
          switch (x.args) {
            VMap(:final v) =>
              v['agg'] != const VStr('min') && v['agg'] != const VStr('max'),
            _ => true,
          })
        x.key,
  ];

  setUp(() async {
    login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    api
      ..children_[base] = [Child('ahu', NodeMeta()), Child('vav', NodeMeta())]
      ..children_['$base/ahu'] = [
        for (final (i, k) in [a, b, c, d].indexed)
          Child('w$i', NodeMeta(display: k)),
      ]
      ..children_['$base/vav'] = [Child('w9', NodeMeta(display: a))];
    for (final k in [a, b, c, d]) {
      api.histories[k] = [
        const HistRow(1794108760000000, VFloat(1), Quality.good),
        const HistRow(1794108761000000, VFloat(2), Quality.good),
      ];
    }
  });

  test('open and refresh list groups and points, no recorded values', () async {
    await s.dispatchAndWait(RetrieveHistorianAction());
    await s.dispatchAndWait(RetrieveHistorianAction());
    expect(s.state.historian.groups.map((g) => g.name), ['ahu', 'vav']);
    expect(s.state.historian.groups.first.keys, [a, b, c, d]);
    expect(s.state.historian.points, isEmpty);
    // A series is read only for a point picked: none yet.
    await s.dispatchAndWait(RetrieveSeriesAction());
    expect(historyReads(), isEmpty);
    expect(s.state.historian.series, isEmpty);
  });

  test(
    'a pick reads that point; a range change reads the picked only',
    () async {
      await s.dispatchAndWait(RetrieveHistorianAction());
      s.dispatchSync(PickPointAction(b));
      await s.dispatchAndWait(RetrieveSeriesAction());
      expect(historyReads(), [b]);
      expect(s.state.historian.series.keys, [b]);

      api.calls.clear();
      s
        ..dispatchSync(PickPointAction(d, add: true))
        ..dispatchSync(SetRangeAction('7d'));
      await s.dispatchAndWait(RetrieveSeriesAction());
      expect(historyReads()..sort(), [b, d]);
      expect(s.state.historian.series.keys.toSet(), {b, d});
    },
  );

  test('a plain pick replaces, an added one joins up to three', () async {
    await s.dispatchAndWait(RetrieveHistorianAction());
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(PickPointAction(b));
    expect(s.state.historian.points, [b]);
    s
      ..dispatchSync(PickPointAction(c, add: true))
      ..dispatchSync(PickPointAction(a, add: true))
      ..dispatchSync(PickPointAction(d, add: true));
    expect(s.state.historian.points, [c, a, d]);
    s.dispatchSync(PickPointAction(a, add: true));
    expect(s.state.historian.points, [c, d]);
    // A second plain pick of the only point clears it.
    s
      ..dispatchSync(PickPointAction(c))
      ..dispatchSync(PickPointAction(c));
    expect(s.state.historian.points, isEmpty);
  });

  test('another group starts with no point picked', () async {
    await s.dispatchAndWait(RetrieveHistorianAction());
    s.dispatchSync(PickPointAction(a));
    await s.dispatchAndWait(RetrieveSeriesAction());
    s.dispatchSync(SetSelectedAction('vav'));
    expect(s.state.historian.points, isEmpty);
    expect(s.state.historian.series, isEmpty);
  });

  test('a picked point no longer recorded leaves on refresh', () async {
    await s.dispatchAndWait(RetrieveHistorianAction());
    s.dispatchSync(PickPointAction(b));
    api.children_['$base/ahu'] = [Child('w0', NodeMeta(display: a))];
    await s.dispatchAndWait(RetrieveHistorianAction());
    expect(s.state.historian.points, isEmpty);
  });
}
