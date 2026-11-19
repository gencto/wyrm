import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flows/actions/retrieve_flows_action.dart';
import 'package:business/redux/live/actions/apply_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_val.dart';
import 'package:business/wyrm/mappers/flow_value_mapper.dart';
import 'package:business/wyrm/mappers/live_overlay_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/flow_summary.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// A flow whose `~val` Studio cannot read is never a draft (audit of
/// #135): the decoder refuses a field of another type, and the summary
/// says its state is not known.
void main() {
  final warned = <String>[];
  setUpAll(() {
    Logger.root.level = Level.ALL;
    decodeLog.onRecord.listen((r) => warned.add(r.message));
  });
  setUp(warned.clear);

  group('the decoder', () {
    test('a field of another type is refused with its name', () {
      for (final (value, field, reason) in <(Object?, String, String)>[
        ({'state': 'running'}, 'state', 'not a whole number'),
        ({'state': 0.5}, 'state', 'not a whole number'),
        ({'state': true}, 'state', 'not a whole number'),
        ({'state': 0, 'version': 'v4'}, 'version', 'not a whole number'),
        ({'state': 2, 'error': 7}, 'error', 'not a text'),
        ({'state': 0, 'deployed_by': 3}, 'deployed_by', 'not a text'),
        ('running', '', 'not a map'),
        ([0, 4], '', 'not a map'),
      ]) {
        expect(
          flowValOf(value),
          Invalid<FlowVal>('flow value', field, reason),
          reason: '$value',
        );
      }
    });

    test('no value, and a value without a state, is a draft', () {
      expect(flowValOf(null), const Valid(FlowVal()));
      expect(flowValOf(<String, Object?>{}), const Valid(FlowVal()));
      final draft = flowSummaryOfValue('f', null);
      expect(
        (draft.draft, draft.running, draft.unreadable),
        (
          true,
          false,
          false,
        ),
      );
      expect(warned, isEmpty);
    });
  });

  group('the summary', () {
    test('a running flow with a state Studio cannot read is not a draft', () {
      for (final value in <Object?>[
        {'state': 'running', 'version': 4},
        {'state': 0, 'version': 'four'},
        'running',
        7,
      ]) {
        final f = flowSummaryOfValue('pump', value, description: 'Pump');
        expect(f.unreadable, isTrue, reason: '$value');
        expect(f.draft, isFalse, reason: '$value');
        expect(f.running, isFalse, reason: '$value');
        expect(f.problem, isNull);
        expect(f.description, 'Pump');
      }
      // a summary records nothing: the value is recorded where it arrives
      expect(warned, isEmpty);
    });

    test('a value it reads is as before', () {
      final f = flowSummaryOfValue('pump', {'state': 0, 'version': 2});
      expect(
        (f.running, f.draft, f.unreadable, f.version),
        (
          true,
          false,
          false,
          2,
        ),
      );
      expect(
        flowSummaryOf(
          'pump',
          const Valid(FlowVal(state: 2, error: 'no rights')),
        ),
        const FlowSummary(id: 'pump', problem: 'no rights'),
      );
    });
  });

  group('the live value over a row (Flows while it is shown)', () {
    LiveValue live(Object? value) =>
        LiveValue(time: DateTime.utc(2026), value: value);

    test('a row that ran, a live value Studio cannot read: the state is '
        'not known, the last version read stays', () {
      const row = FlowSummary(
        id: 'pump',
        version: 3,
        running: true,
        deployedBy: 'user:olena',
      );
      for (final value in <Object?>[
        {'state': 'running', 'version': 3},
        {'state': 0, 'version': 'three'},
        'running',
      ]) {
        final shown = liveFlow(row, live(value));
        expect(shown.unreadable, isTrue, reason: '$value');
        // neither "stopped v3" nor a draft
        expect(shown.running, isFalse, reason: '$value');
        expect(shown.draft, isFalse, reason: '$value');
        expect(shown.problem, isNull, reason: '$value');
        expect(shown.version, 3, reason: '$value');
        expect(shown.deployedBy, 'user:olena', reason: '$value');
      }
    });

    test('a row that was not read, a live value Studio reads: it is '
        'readable again', () {
      const row = FlowSummary(id: 'pump', unreadable: true);
      final running = liveFlow(row, live({'state': 0, 'version': 3}));
      expect(
        (running.unreadable, running.running, running.draft, running.version),
        (false, true, false, 3),
      );
      final failed = liveFlow(
        row.copyWith(version: 3),
        live({'state': 2, 'error': 'no rights'}),
      );
      expect(
        (failed.unreadable, failed.problem, failed.version),
        (
          false,
          'no rights',
          3,
        ),
      );
      // back and forth: each value decides by itself
      final again = liveFlow(running, live({'state': 'running'}));
      expect(
        (again.unreadable, again.running, again.version),
        (true, false, 3),
      );
      expect(liveFlow(again, live({'state': 0})).unreadable, isFalse);
    });

    test('no live value leaves the row as it was read', () {
      const row = FlowSummary(id: 'pump', unreadable: true);
      expect(liveFlow(row, null), row);
    });

    test('reading it records nothing; the batch it arrives in records it '
        'once', () {
      const row = FlowSummary(id: 'pump', version: 3, running: true);
      final bad = live({'state': 'running'});
      for (var i = 0; i < 5; i++) {
        liveFlow(row, bad);
      }
      expect(warned, isEmpty);

      warnUnreadLive({
        'wy/central/dataflows/pump': bad,
        'wy/central/dataflows/ok': live({'state': 0}),
        // a value under a flow is not its `~val`
        'wy/central/dataflows/pump/nodes/n1': live('x'),
        'wy/central/dataflows/gone': null,
      }, 'wy/central');
      expect(warned, [
        'wy/central/dataflows/pump: flow value.state: not a whole number',
      ]);
    });
  });

  group('RetrieveFlowsAction', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    setUp(() async {
      final login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());
    });

    test(
      'lists a flow it cannot read as one whose state is not known',
      () async {
        const base = 'wy/central/dataflows';
        ValSample at(String id, Value v) =>
            ValSample('$base/$id', Sample(v, t: 1));
        api
          ..children_[base] = [
            Child('ok', NodeMeta()),
            Child('odd', NodeMeta(display: 'Odd one')),
            Child('new', NodeMeta()),
          ]
          ..initial['$base/*'] = [
            at('ok', const VMap({'state': VInt(0), 'version': VInt(3)})),
            // the broker says it runs, in a form this Studio does not read
            at(
              'odd',
              const VMap({'state': VStr('running'), 'version': VInt(3)}),
            ),
          ];

        await s.dispatchAndWait(RetrieveFlowsAction());

        final flows = s.state.flows.table;
        expect(flows.keys, containsAll(['ok', 'odd', 'new']));
        expect(flows['ok']!.running, isTrue);
        expect(flows['odd']!.unreadable, isTrue);
        expect(flows['odd']!.draft, isFalse);
        expect(flows['odd']!.description, 'Odd one');
        // never deployed: no value at all
        expect(flows['new']!.draft, isTrue);
        expect(flows['new']!.unreadable, isFalse);
        expect(
          warned,
          contains('$base/odd: flow value.state: not a whole number'),
        );

        // Live, while Flows is shown: `ok` now answers in a form Studio
        // does not read, `odd` in one it reads. Each is recorded once,
        // however often the screen reads the table.
        warned.clear();
        await s.dispatchAndWait(
          ApplyLiveValuesAction({
            '$base/ok': LiveValue(
              time: DateTime.utc(2026),
              value: const {'state': 'running', 'version': 3},
            ),
            '$base/odd': LiveValue(
              time: DateTime.utc(2026),
              value: const {'state': 0, 'version': 4},
            ),
          }),
        );
        for (var i = 0; i < 4; i++) {
          final shown = SelectFlows(s.state).shownTable;
          expect(shown['ok']!.unreadable, isTrue);
          expect(shown['ok']!.running, isFalse);
          expect(shown['ok']!.version, 3, reason: 'the last version read');
          expect(shown['odd']!.unreadable, isFalse);
          expect(shown['odd']!.running, isTrue);
        }
        expect(
          warned.where((w) => w.contains('flow value')),
          ['$base/ok: flow value.state: not a whole number'],
        );
      },
    );
  });
}
