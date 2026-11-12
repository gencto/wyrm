import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/load_trend_extremes_action.dart';
import 'package:business/redux/historian/actions/load_trend_window_action.dart';
import 'package:business/redux/historian/actions/pick_point_action.dart';
import 'package:business/redux/historian/actions/retrieve_series_action.dart';
import 'package:business/redux/historian/actions/set_range_action.dart';
import 'package:business/redux/historian/actions/set_trend_window_action.dart';
import 'package:business/redux/historian/actions/toggle_trend_series_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/history_steps.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/hist_window.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// The trend's data (spec trend.md §4): the range coarse, the window finer
/// once it stops moving, the buckets' min and max after, every change
/// superseding a read in flight.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  const a = 'wy/central/downstream/m/a';
  const b = 'wy/central/downstream/m/b';

  Map<String, Value> args(Call c) => switch (c.args) {
    VMap(:final v) => v,
    _ => const {},
  };
  List<Map<String, Value>> reads() => [
    for (final c in api.calls)
      if (c.op == 'history') args(c),
  ];
  String? str(Value? v) => v is VStr ? v.v : null;

  setUp(() async {
    final login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    final t0 = DateTime.now().toUtc().microsecondsSinceEpoch;
    for (final k in [a, b]) {
      api.histories[k] = [
        HistRow(t0 - 600000000, const VFloat(1), Quality.good),
        HistRow(t0 - 300000000, const VFloat(2), Quality.uncertain),
      ];
      api.histories['$k ▸ min'] = [
        HistRow(t0 - 600000000, const VFloat(0.5)),
      ];
      api.histories['$k ▸ max'] = [
        HistRow(t0 - 600000000, const VFloat(1.5)),
      ];
    }
  });

  test('the ladder: ≤ 300 buckets of the finest step, raw up to 2 h', () {
    expect(stepFor(const Duration(hours: 1)), isNull);
    expect(stepFor(const Duration(hours: 1), raw: false), '1m');
    expect(stepFor(const Duration(hours: 6)), '5m');
    expect(stepFor(const Duration(hours: 24)), '5m');
    expect(stepFor(const Duration(days: 7)), '1h');
    expect(stepFor(const Duration(days: 30)), '6h');
  });

  test('the range reads avg at its step, then min and max', () async {
    s.dispatchSync(PickPointAction(a));
    await s.dispatchAndWait(RetrieveSeriesAction());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final r = reads();
    expect([for (final x in r) str(x['agg'])], ['avg', 'min', 'max']);
    expect({for (final x in r) str(x['window'])}, {'5m'});
    expect(s.state.historian.series[a]!.length, 2);
    expect(s.state.historian.low[a]!.single.value, 0.5);
    expect(s.state.historian.high[a]!.single.value, 1.5);
  });

  test('a range change forgets the old min and max', () async {
    s.dispatchSync(PickPointAction(a));
    await s.dispatchAndWait(RetrieveSeriesAction());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.state.historian.low, isNotEmpty);
    s.dispatchSync(SetRangeAction('7d'));
    expect(s.state.historian.low, isEmpty);
    expect(s.state.historian.high, isEmpty);
  });

  test('a point never opened gets its unit from a quiet meta read', () async {
    api.metas[a] = NodeMeta(unit: const TText('°C'));
    s.dispatchSync(PickPointAction(a));
    await s.dispatchAndWait(RetrieveSeriesAction());
    expect(s.state.nodes.detail[a]?.unit, '°C');
    // A refusal leaves it out, with no dialog and no problem.
    s.dispatchSync(PickPointAction(b));
    await s.dispatchAndWait(RetrieveSeriesAction());
    expect(s.state.nodes.detail[b], isNull);
    expect(s.state.problems.items, isEmpty);
  });

  test('a window of 1 h reads raw rows with their quality', () async {
    s.dispatchSync(PickPointAction(a));
    await s.dispatchAndWait(RetrieveSeriesAction());
    api.calls.clear();
    s.dispatchSync(
      SetTrendWindowAction(const HistWindow(span: Duration(hours: 1))),
    );
    await s.dispatchAndWait(LoadTrendWindowAction());
    final r = reads().where((x) => x['agg'] == null).toList();
    expect(r, hasLength(1));
    expect(r.single['limit'], const VInt(rawLimit));
    // A window that follows now reads up to now.
    expect(str(r.single['to']), '');
    final d = s.state.historian.detail!;
    expect(d.step, 'raw');
    expect(d.points[a]!.last.quality, 'uncertain');
  });

  test('a key at the raw limit is read again as 1 min buckets', () async {
    final t0 = DateTime.now().toUtc().microsecondsSinceEpoch;
    api.histories[a] = [
      for (var i = 0; i < rawLimit; i++)
        HistRow(t0 - i * 100000, const VFloat(1), Quality.good),
    ];
    api.histories['$a ▸ 1m'] = [HistRow(t0, const VFloat(3))];
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(
        SetTrendWindowAction(
          HistWindow(
            span: const Duration(minutes: 30),
            end: DateTime.now().toUtc(),
          ),
        ),
      );
    await s.dispatchAndWait(LoadTrendWindowAction());
    final d = s.state.historian.detail!;
    expect(d.step, '1m');
    expect(d.points[a]!.single.value, 3);
    expect(str(reads().first['to']), isNotEmpty);
  });

  test('a rollup window gets its min and max', () async {
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(
        SetTrendWindowAction(const HistWindow(span: Duration(hours: 6))),
      );
    await s.dispatchAndWait(LoadTrendWindowAction());
    expect(s.state.historian.detail!.step, '5m');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.state.historian.detail!.low[a]!.single.value, 0.5);
    expect(s.state.historian.detail!.high[a]!.single.value, 1.5);
  });

  test('live rows of a following window keep its min and max', () async {
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(
        SetTrendWindowAction(const HistWindow(span: Duration(hours: 6))),
      );
    await s.dispatchAndWait(LoadTrendWindowAction());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The extremes read again while a live batch grows the window's rows.
    final read = s.dispatchAndWait(LoadTrendExtremesAction(detail: true));
    s.dispatchSync(
      UpdateStateAction<AppState>.withReducer((st) {
        final d = st.historian.detail!;
        return st.copyWith.historian(
          detail: d.copyWith(
            to: DateTime.now().toUtc(),
            low: const IMapConst({}),
            high: const IMapConst({}),
          ),
        );
      }),
    );
    await read;
    expect(s.state.historian.detail!.low[a]!.single.value, 0.5);
  });

  test('a range change ends the window; its late answer is dropped', () async {
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(
        SetTrendWindowAction(const HistWindow(span: Duration(hours: 6))),
      );
    final gen = s.state.historian.trendGen;
    final late = s.dispatchAndWait(LoadTrendWindowAction());
    s.dispatchSync(SetRangeAction('7d'));
    await late;
    expect(s.state.historian.trendGen, greaterThan(gen));
    expect(s.state.historian.window, isNull);
    expect(s.state.historian.detail, isNull);
  });

  test('a legend toggle hides a series; an unpick forgets it', () {
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(PickPointAction(b, add: true))
      ..dispatchSync(ToggleTrendSeriesAction(b));
    expect(s.state.historian.hidden, {b});
    s.dispatchSync(ToggleTrendSeriesAction(b));
    expect(s.state.historian.hidden, isEmpty);
    s
      ..dispatchSync(ToggleTrendSeriesAction(b))
      ..dispatchSync(PickPointAction(b, add: true));
    expect(s.state.historian.points, [a]);
    expect(s.state.historian.hidden, isEmpty);
  });

  test('Reset zoom drops the window and its rows', () async {
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(
        SetTrendWindowAction(const HistWindow(span: Duration(hours: 1))),
      );
    await s.dispatchAndWait(LoadTrendWindowAction());
    expect(s.state.historian.detail, isNotNull);
    s.dispatchSync(SetTrendWindowAction(null));
    expect(s.state.historian.window, isNull);
    expect(s.state.historian.detail, isNull);
  });

  test('a point the viewer may not read is never queried', () async {
    final login = FakeLogin(
      session: FakeSession(
        who: const WhoAmI(
          subject: 'user:olena',
          site: 'central',
          roles: ['operator'],
          max: 'read',
          grants: [('wy/central/downstream/m/a', 'read')],
        ),
      ),
    );
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('olena'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    s
      ..dispatchSync(PickPointAction(a))
      ..dispatchSync(PickPointAction(b, add: true));
    await s.dispatchAndWait(RetrieveSeriesAction());
    expect(
      {
        for (final c in api.calls)
          if (c.op == 'history') c.key,
      },
      {a},
    );
  });
}
