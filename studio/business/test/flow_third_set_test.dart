import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/trigger_block_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/table_value.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/catalog_0226.dart';
import 'support/catalog_0229.dart';
import 'support/fake_wyrm.dart';

// The flow editor and the third set of blocks (ADR 0044, spec 06 0.2.29,
// docs/flow-blocks.md "How the editor shows each block"), on the catalog a
// broker with it answers (125 types).

final Map<String, NodeType> types = {
  for (final t in catalog0229())
    t['type']! as String: nodeTypeOf(Value.from(t)),
};

FlowBlock block(String type, [Map<String, Object?> cfg = const {}]) =>
    FlowBlock(id: 'b', type: type, cfg: cfg.lock);

/// The labels of the rows a new block of [type] draws, in order.
List<String> rows(String type, [Map<String, Object?> cfg = const {}]) => [
  for (final f in rowsOf(types[type], block(type, cfg))) f.label,
];

FlowField field(
  String type,
  String id, [
  Map<String, Object?> cfg = const {},
]) => fieldsOf(types[type], block(type, cfg)).firstWhere((f) => f.id == id);

void main() {
  test('the catalog has the 125 types and the labels the engine gives', () {
    expect(types, hasLength(125));
    // `params[].display` (spec 06 0.2.29) is the row's label.
    expect(
      types['atan']!.params.firstWhere((p) => p.name == 'x').display,
      'X',
    );
    expect(field('atan', 'p:x').label, 'X');
  });

  test('the palette lists the new sections in order, a new one last', () {
    final cats = <String>{
      for (final t in inPaletteOrder(types.values)) t.category,
    }.toList();
    expect(cats, [
      'Sources',
      'Variables',
      'Math',
      'Trigonometry',
      'Statistics',
      'Logic',
      'Text',
      'Codecs',
      'Data',
      'Tables',
      'Date and time',
      'Alarms',
      'Outputs',
      'WASM',
    ]);
    final more = inPaletteOrder([
      const NodeType(type: 'x', category: 'Vision'),
      ...types.values,
    ]);
    expect(more.last.type, 'x', reason: 'an unknown section comes last');
    // Within a section the catalog's order stays.
    final sources = [
      for (final t in inPaletteOrder(types.values))
        if (t.category == 'Sources') t.type,
    ];
    expect(sources.take(4), ['subscribe', 'timer', 'const', 'liveliness']);
  });

  group('router: a case and its output are one field', () {
    test('Case 1 ⇄ is in.0 on the left and out.0 on the right', () {
      expect(rows('router'), [
        'Input',
        'Condition',
        'Operation',
        'Case 1',
        'Case 2',
        'Single output',
        'Else',
      ]);
      final c = field('router', 'in:in.0');
      expect((c.inPort, c.outPort), ('in.0', 'out.0'));
      expect(c.operand, isTrue, reason: 'a case value is a constant');
      expect(
        fieldsOf(types['router'], block('router')).map((f) => f.outPort),
        isNot(contains('in.0')),
        reason: 'no echo of the case beside its output',
      );
      // Named cases keep their names.
      expect(
        rows('router', {
          'inputs': ['high', 'low'],
        }),
        containsAllInOrder(['high', 'low']),
      );
      expect(
        field('router', 'in:in.high', {
          'inputs': ['high', 'low'],
        }).outPort,
        'out.high',
      );
    });

    test('− / + adds a case and its output (the store test removes both)', () {
      final v = variadicOf(types['router'], block('router'))!;
      expect(v.outPrefix, 'out.');
      expect(v.step, 1);
      expect(v.adds, ['2']);
      expect(pairsOutputs(types['router']), isTrue);
      expect(pairsOutputs(types['wasm']), isFalse);
      expect(variadicOf(types['wasm'], block('wasm')), isNull);
    });
  });

  test('readers: the point is their key, Node for get_node, the query on '
      'the block and limit and zone in the inspector', () {
    expect(
      pointOf(block('load_history', {'key': 'downstream/m/t'})),
      'downstream/m/t',
    );
    expect(pointOf(block('get_node', {'key': 'downstream/m'})), 'downstream/m');
    expect(rows('load_history'), [
      'Point',
      'Time range',
      'Rollup',
      'Window',
      'Trigger',
      'Error',
      'Output',
    ]);
    expect(rows('get_node').first, 'Node');
    // Every reader runs on `~act/trigger` (the Run button).
    for (final r in [
      'load_value',
      'list_children',
      'load_history',
      'get_node',
    ]) {
      expect(types[r]!.trigger, isTrue, reason: r);
      expect(behavesOf(types[r]), isTrue, reason: r);
    }
  });

  test('the commands of date_range and table_page are buttons', () {
    for (final (type, port) in [
      ('date_range', 'next'),
      ('date_range', 'previous'),
      ('table_page', 'first'),
      ('table_page', 'last'),
    ]) {
      final f = field(type, 'in:$port');
      expect(f.command, isTrue, reason: '$type.$port');
      expect(f.inPort, port, reason: 'a wire presses it');
      expect(f.outPort, isNull, reason: 'it feeds nothing');
      expect(f.outAliases, [port], reason: 'an older wire still draws');
      expect(f.operand, isFalse, reason: 'it holds no constant');
    }
    expect(field('date_range', 'in:in').command, isFalse);
  });

  test('order and labels as the editor table says', () {
    expect(rows('table_recorder'), [
      'Reset',
      'Input 1',
      'Input 2',
      'Enabled',
      'Buffer size',
      'Time window (s)',
      'Ignore null',
      'Output',
    ]);
    expect(rows('date_range'), [
      'Input',
      'Next',
      'Previous',
      'Format',
      'Delimiter',
      'Keep special',
      'Week start',
      'Time zone',
      'Start',
      'End',
      'This range',
      'Next range',
      'Previous range',
      'Formatted',
      'Duration',
    ]);
    expect(rows('constant'), ['Name', 'Value']);
    expect(rows('table_filter'), ['Input', 'Output', 'Error']);
    expect(rows('table_map_columns'), [
      'Input',
      'Retain columns',
      'Output',
      'Error',
    ]);
    expect(rows('event_gate'), [
      'Reset',
      'Log order',
      'Input 1',
      'Input 2',
      'On finish',
      'Order',
    ]);
    // Block names by the broker's rule (ADR 0042).
    expect(blockLabel('json_parse'), 'JSON parse');
    expect(blockLabel('table_to_csv'), 'Table to CSV');
  });

  group('dates', () {
    final at = DateTime.utc(2026, 11, 11, 10, 29, 3).microsecondsSinceEpoch;

    test('a date is microseconds, read as a date and time', () {
      final local = DateTime.fromMicrosecondsSinceEpoch(
        at,
        isUtc: true,
      ).toLocal();
      String two(int n) => '$n'.padLeft(2, '0');
      expect(
        dateText(at),
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:03',
      );
      expect(dateTextUtc(at), '2026-11-11T10:29:03Z');
      expect(dateText(1.5), isNull);
      expect(dateText('today'), isNull);
    });

    test('the date fields of the date blocks show it', () {
      expect(isTimeField('now', 'out'), isTrue);
      expect(isTimeField('date_range', 'start'), isTrue);
      expect(isTimeField('date_range', 'duration'), isFalse);
      final b = block('now');
      final out = field('now', 'out:out');
      final d = FlowDraft(id: 'f', blocks: {'b': b}.lock);
      final v = fieldValue(
        b,
        out,
        d,
        (k) => k == portKey('out', 'b', 'out')
            ? LiveValue(time: DateTime.utc(2026), value: at)
            : null,
      );
      expect(v.text, dateText(at));
      expect(v.raw, at, reason: 'the viewer keeps the number');
    });

    test('a time zone field offers zones, date_format also auto; a range '
        'text its choices', () {
      expect(isTimeZoneParam('date_format', 'time_zone'), isTrue);
      expect(isTimeZoneParam('load_history', 'time_zone'), isTrue);
      expect(isTimeZoneParam('table_rollup', 'time_zone'), isTrue);
      expect(timeZoneChoicesOf('date_format').first, 'auto');
      expect(timeZoneChoicesOf('date_time').first, 'UTC');
      expect(timeZoneChoices, containsAll(['Europe/Kyiv', '+02:00']));
      expect(isRangeText('date_range', 'in'), isTrue);
      expect(isRangeText('load_history', 'time_range'), isTrue);
      expect(
        rangeChoices,
        containsAll(['today', 'lastWeek', 'current24hours']),
      );
      // The range of a `date_range` is its operand: typed into `values`,
      // as a text: `2026` is a year, not a number.
      final range = field('date_range', 'in:in');
      expect(range.operand, isTrue);
      final how = fieldEditOf(block('date_range'), range, const []).edit!;
      expect(how, FieldEdit.text);
      expect(typedText('2026', how), '2026');
      // Another operand still reads JSON.
      expect(
        typedText(
          '2',
          fieldEditOf(block('sin'), field('sin', 'in:in'), const []).edit!,
        ),
        2,
      );
    });
  });

  group('tables', () {
    test('the fields whose table the viewer edits in its grid', () {
      // The `table` variable's Value holds a table typed as JSON; a wire
      // into it makes it read only.
      final t = block('table', {
        'value': {
          'columns': ['a'],
          'rows': [
            {'a': 1},
          ],
        },
      });
      final value = fieldsOf(
        types['table'],
        t,
      ).firstWhere((f) => f.spec?.name == 'value');
      expect(holdsTable(types['table'], value.name), isTrue);
      expect(fieldEditOf(t, value, const []).edit, FieldEdit.json);
      expect(fieldEditValue(t, value), {
        'columns': ['a'],
        'rows': [
          {'a': 1},
        ],
      });
      final wire = FlowEdge(
        from: 'x',
        fromPort: 'out',
        to: t.id,
        toPort: value.inPort!,
      );
      expect(fieldEditOf(t, value, [wire]).locked, FieldLocked.bound);
      // A typed operand of a table block holds a table too.
      final sort = field('table_sort', 'in:in');
      expect(holdsTable(types['table_sort'], sort.name), isTrue);
      expect(
        fieldEditOf(block('table_sort'), sort, const []).edit,
        FieldEdit.any,
      );
      // The CSV text of `table_from_csv` stays a text (its "As table" tab).
      final csv = field('table_from_csv', 'in:in');
      expect(
        fieldEditOf(block('table_from_csv'), csv, const []).edit,
        FieldEdit.text,
      );
      // An output is never typed.
      final out = field('table_sort', 'out:out');
      expect(fieldEditOf(block('table_sort'), out, const []).edit, isNull);
    });

    test('{columns, rows} is a table, rows by name or by position', () {
      final t = tableOf({
        'columns': ['name', 'kw'],
        'rows': [
          {'name': 'pump', 'kw': 3},
          ['fan', 7.5],
          {'name': 'gap'},
        ],
      })!;
      expect(t.columns, ['name', 'kw']);
      expect(t.rows, [
        ['pump', 3],
        ['fan', 7.5],
        ['gap', null],
      ]);
    });

    test('a list of maps is a table only where a table is expected', () {
      final rows = [
        {'t': DateTime.utc(2026).microsecondsSinceEpoch, 'v': 1, 'q': 0},
        {'t': DateTime.utc(2026).microsecondsSinceEpoch, 'v': 2, 'x': true},
      ];
      expect(tableOf(rows), isNull, reason: 'the Explorer keeps a list');
      final t = tableOf(rows, rowsOfMaps: true)!;
      expect(t.columns, ['t', 'v', 'q', 'x']);
      expect(
        tableCellText('t', rows[0]['t']),
        dateText(rows[0]['t']),
        reason: 't is a date',
      );
      expect(tableCellText('v', 1), isNull);
      expect(holdsTable(types['load_history'], 'out'), isTrue);
      expect(holdsTable(types['get_node'], 'actions'), isTrue);
      expect(holdsTable(types['table_sort'], 'out'), isTrue);
      expect(holdsTable(types['add'], 'out'), isFalse);
      expect(
        tableOf({
          'columns': ['a'],
          'rows': [1],
        }),
        isNull,
      );
    });

    test('mapping and aggregates are edited as rows', () {
      final m = listItemsOf(types['table_map_columns'], 'mapping')!;
      expect([for (final c in m) c.key], ['name', 'from']);
      final a = listItemsOf(types['table_rollup'], 'aggregates')!;
      expect([for (final c in a) c.key], ['column', 'method', 'as']);
      expect(a[1].choices, contains('concat_unique'));
      expect(
        listItemsOf(types['table_group_by'], 'aggregates')![1].choices,
        aggregateMethods,
        reason: 'no method parameter: the engine list',
      );
      expect(listItemsOf(types['table_sort'], 'column'), isNull);
      expect(
        listRowsOf([
          {'column': 'v', 'method': 'max', 'as': 't_max'},
          {'column': 'n', 'method': 'count', 'as': null},
          3,
        ]),
        [
          {'column': 'v', 'method': 'max', 'as': 't_max'},
          {'column': 'n', 'method': 'count', 'as': ''},
        ],
      );
    });
  });

  group('in the store', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    final flow = {
      'id': 'hist',
      'version': 1,
      'nodes': {
        'h': {
          'type': 'load_history',
          'key': 'downstream/m/t',
          'time_range': 'today',
        },
        'r': {
          'type': 'router',
          'inputs': ['0', '1', '2'],
        },
        'w': {'type': 'set', 'path': 'downstream/m/sp'},
      },
      'edges': [
        ['h.out', 'r.in'],
        ['r.out.2', 'w.in'],
      ],
    };

    setUp(() async {
      final login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());
      api
        ..invokes['wy/central/dataflows ▸ node_types'] = [
          Value.from(catalog0229()),
        ]
        ..invokes['wy/central/dataflows/hist ▸ history'] = [
          Value.from([flow]),
        ]
        ..invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': true}),
        ];
      await s.dispatchAndWait(LoadFlowAction('hist'));
    });

    test('removing a case of a router takes its output and its wire', () async {
      final r = s.state.flowEditor.draft!.edges;
      expect(r.where((e) => e.fromPort == 'out.2'), hasLength(1));
      await s.dispatchAndWait(ResizeInputsAction('r', add: false));
      final d = s.state.flowEditor.draft!;
      expect(d.blocks['r']!.cfg['inputs'], ['0', '1']);
      expect(d.edges.where((e) => e.fromPort == 'out.2'), isEmpty);
      expect(d.edges, hasLength(1), reason: 'the reader stays wired');
    });

    test("a refused Run of a reader shows the broker's words", () async {
      api.errors['wy/central/dataflows/hist ▸ trigger'] = WyrmException.of(
        Status.permissionDenied,
        'w (downstream of h): wy/central/downstream/m/sp: the caller does '
        'not hold write on it',
      );
      final r = await s.dispatchAndWait(TriggerBlockAction('h'));
      final reason = switch (r.originalError) {
        final UserException e => e.reason,
        _ => null,
      };
      expect(reason, contains('w (downstream of h)'));
      expect(reason, contains('does not hold write'));
      // No words from the broker: Studio says it.
      expect(
        triggerRefusal(WyrmException.of(Status.permissionDenied, '')),
        contains('needs write'),
      );
    });
  });

  test('an older catalog keeps its shape', () {
    final old = {
      for (final t in catalog0226())
        t['type']! as String: nodeTypeOf(Value.from(t)),
    };
    expect(old['router'], isNull);
    expect(old['load_value']!.params.first.display, isNull);
    expect(
      fieldsOf(old['load_value'], block('load_value')).first.label,
      'Point',
    );
  });

  // The owner's screenshots of 2026-11-11 (spec 06 0.2.30).
  test('liveliness reads Node and Alive; subscribe its point', () {
    expect(rows('liveliness'), ['Node', 'Alive']);
    expect(
      rows('liveliness', {'key': 'downstream/modbus'}),
      ['Node', 'Alive'],
      reason: 'a presence, not a value named after the node',
    );
    expect(rows('subscribe'), ['Point', 'Output']);
    expect(rows('subscribe', {'key': 'downstream/modbus/t1'}), [
      'Point',
      't1',
    ]);
  });

  test('a CSV typed as a text keeps its lines and stays a text', () {
    final b = block('table_from_csv');
    final f = field('table_from_csv', 'in:in');
    final edit = fieldEditOf(b, f, const []).edit;
    expect(edit, FieldEdit.text);
    expect(typedText('a,b\n1,2', edit!), 'a,b\n1,2');
    // a one-line `5` is the text `5`, not the number JSON makes of it
    expect(typedText('5', edit), '5');
    expect(isTextOperand('split', 'in'), isTrue);
    // an operand of another block still reads JSON
    final add = fieldEditOf(block('add'), field('add', 'in:in.0'), const []);
    expect(add.edit, FieldEdit.any);
  });
}
