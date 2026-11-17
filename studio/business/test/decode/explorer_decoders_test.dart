import 'package:business/wyrm/decode/action_answer.dart';
import 'package:business/wyrm/decode/audit_entry.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/hist_point.dart';
import 'package:business/wyrm/decode/live_values.dart';
import 'package:business/wyrm/decode/point_edit.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/action_info.dart';
import 'package:models/driver_status.dart';
import 'package:models/link_state.dart';
import 'package:models/modbus_area.dart';
import 'package:models/param_spec.dart';
import 'package:models/point_param.dart';
import 'package:models/point_register.dart';
import 'package:models/quality.dart' as studio;
import 'package:models/word_order.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The shapes Explorer reads, decoded once (studio-rules §8): an audit
/// record, an action's answer, a history row, and the live samples of a
/// link's state, a broker's `connected` and a flow's `~val`.
/// The value of a [Valid]; fails the test on an [Invalid].
T valid<T>(Decoded<T> d) => switch (d) {
  Valid(:final value) => value,
  Invalid() => throw TestFailure('$d'),
};

void main() {
  group('audit record', () {
    test('a record with every field', () {
      final r = auditEntryOf(
        Value.from({
          't': 1700000000000000,
          'op': 'set',
          'key': 'wy/p/downstream/m/sp',
          'sub': 'user:olena',
          'status': 3,
        }),
      );
      final e = valid(r);
      expect(e.key, 'wy/p/downstream/m/sp');
      expect(e.op, 'set');
      expect(e.who, 'user:olena');
      expect(e.status, 3);
      expect(e.time.microsecondsSinceEpoch, 1700000000000000);
    });

    test('no op, no sub, no status: empty and 0', () {
      final r = auditEntryOf(Value.from({'t': 5, 'key': 'k'}));
      final e = valid(r);
      expect((e.op, e.who, e.status), ('', '', 0));
    });

    test('no key, no time, or no map is invalid with the field', () {
      expect(
        auditEntryOf(Value.from({'t': 5})),
        const Invalid<Object>('audit record', 'key', 'missing'),
      );
      expect(
        auditEntryOf(Value.from({'key': 'k'})),
        const Invalid<Object>('audit record', 't', 'missing'),
      );
      expect(
        auditEntryOf(Value.from('x')),
        const Invalid<Object>('audit record', '', 'not a map'),
      );
    });

    test('rows are records or arrays of them', () {
      final rows = auditEntriesOf([
        Value.from({'t': 1, 'key': 'a'}),
        Value.from([
          {'t': 2, 'key': 'b'},
          {'t': 3},
        ]),
      ]);
      expect(rows, hasLength(3));
      expect(rows.whereType<Valid<Object?>>(), hasLength(2));
    });
  });

  group('action answer', () {
    test('records are a table of their first six fields', () {
      final a = actionAnswerOf([
        Value.from([
          {'addr': 10, 'value': 215},
          {'addr': 11, 'value': null},
        ]),
      ]);
      expect(a.columns.unlock, ['addr', 'value']);
      expect(a.rows.map((r) => r.unlock), [
        ['10', '215'],
        ['11', ''],
      ]);
      expect(a.count, 2);
    });

    test('one record answered alone is a table too', () {
      final a = actionAnswerOf([
        Value.from({'ok': true}),
      ]);
      expect(a.rows.single.unlock, ['true']);
      expect(a.count, 1);
    });

    test('rows that are no records are JSON lines', () {
      final a = actionAnswerOf([Value.from('done'), Value.from(3)]);
      expect(a.rows, isEmpty);
      expect(a.count, 2);
      expect(a.lines.unlock, ['"done"', '3']);
    });

    test('a record is indented JSON, line by line', () {
      final a = actionAnswerOf([
        Value.from({'vendor': 'acme'}),
      ]);
      expect(a.lines.unlock, ['{', '  "vendor": "acme"', '}']);
    });
  });

  group('history row', () {
    test('a number, a bool as 0/1, the quality', () {
      final n = histPointOf(const HistRow(1, VFloat(21.5), Quality.uncertain));
      expect(
        (n.value, n.text, n.quality),
        (
          21.5,
          '21.5',
          studio.Quality.uncertain,
        ),
      );
      final b = histPointOf(const HistRow(1, VBool(true)));
      expect((b.value, b.quality), (1, null));
    });

    test('a map has text only as a whole', () {
      final r = HistRow(1, Value.from({'a': 1}));
      expect(histPointOf(r).text, '');
      expect(histPointOf(r, wholeText: true).text, '{a: 1}');
    });
  });

  group('live samples', () {
    test('a link state by code or by name', () {
      expect(linkStateSampleOf(2), const Valid(LinkState.connected));
      expect(linkStateSampleOf('failed'), const Valid(LinkState.failed));
      expect(linkStateSampleOf(9), isA<Invalid<LinkState>>());
      expect(linkStateSampleOf('gone'), isA<Invalid<LinkState>>());
      expect(linkStateSampleOf(1.5), isA<Invalid<LinkState>>());
    });

    test("a broker's connected is a bool", () {
      expect(brokerConnectedOf(false), const Valid(false));
      expect(brokerConnectedOf('yes'), isA<Invalid<bool>>());
    });

    test("a flow's value: running, an error, a draft, since", () {
      final run = valid(
        flowSampleOf('f', {
          'state': 0,
          'version': 3,
          'deployed_by': 'user:olena',
          'since': 1700000000000000,
        }),
      );
      expect(
        (run.running, run.version, run.deployedBy),
        (
          true,
          3,
          'user:olena',
        ),
      );
      expect(run.since?.microsecondsSinceEpoch, 1700000000000000);
      // an error with no words of its own: an empty problem, `ui` words it
      final err = valid(flowSampleOf('f', {'state': 2}));
      expect(err.problem, '');
      final said = valid(flowSampleOf('f', {'state': 2, 'error': 'boom'}));
      expect(said.problem, 'boom');
      final draft = valid(flowSampleOf('f', null));
      expect(draft.draft, isTrue);
      expect(flowSampleOf('f', 'x'), isA<Invalid<Object?>>());
    });
  });

  group('point edit', () {
    test('a register: modbus area and offset, an address, nothing', () {
      expect(
        pointRegisterOf({'table': 'holding', 'addr': '10'}),
        const PointRegister.modbus(
          addr: '10',
          area: ModbusArea.holding,
          table: 'holding',
        ),
      );
      expect(
        pointRegisterOf({'table': 'fifo', 'addr': '3'}),
        const PointRegister.modbus(addr: '3', table: 'fifo'),
      );
      expect(
        pointRegisterOf({'address': 'DB1.DBX0.0'}),
        const PointRegister.address('DB1.DBX0.0'),
      );
      expect(pointRegisterOf({}), const PointRegister.none());
      expect(pointRegisterOf(null), const PointRegister.none());
    });

    test("a data type's suffix sets its word order", () {
      expect(wordOrderOf('f32'), WordOrder.abcd);
      expect(wordOrderOf('f32_wswap'), WordOrder.cdab);
      expect(wordOrderOf('u32_bswap'), WordOrder.badc);
      expect(wordOrderOf('f64_wbswap'), WordOrder.dcba);
    });

    test('the parameters the board names, and the others', () {
      final params = editParamsOf(
        ActionInfo(
          name: 'edit',
          level: Perm.config,
          params: [
            const ParamSpec(name: 'table'),
            const ParamSpec(name: 'poll_s'),
            const ParamSpec(name: 'own'),
          ].lock,
        ),
      );
      expect(params.map((p) => p.param), [
        PointParam.table,
        PointParam.poll,
        null,
      ]);
    });
  });

  test("a driver's status: its name, and the state this client knows", () {
    final s = driverStatusSampleOf(1, ['connected', 'Connecting', 'gone']);
    expect((s.name, s.status), ('Connecting', DriverStatus.connecting));
    final own = driverStatusSampleOf('warming', const []);
    expect((own.name, own.status), ('warming', null));
  });
}
