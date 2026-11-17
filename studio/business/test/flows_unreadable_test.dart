import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flows/actions/retrieve_flows_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_val.dart';
import 'package:business/wyrm/mappers/flow_value_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/flow_summary.dart';
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
      expect(warned, [
        'flow pump: flow value.state: not a whole number',
        'flow pump: flow value.version: not a whole number',
        'flow pump: flow value.: not a map',
        'flow pump: flow value.: not a map',
      ]);
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
          where: 'test',
        ),
        const FlowSummary(id: 'pump', problem: 'no rights'),
      );
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
      },
    );
  });
}
