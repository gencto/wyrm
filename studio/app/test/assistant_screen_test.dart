import 'dart:convert';
import 'dart:io';

import 'package:app/connectors/assistant_page_connector.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:models/quality.dart' as q;
import 'package:ui/assistant/found_card.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

// The Assistant as the store makes it, written before the screen moved its
// words into `ui` and its wire values into types (studio-rules): every word
// of the tab and of the drawer in each main state, and what each control
// sends to the broker. The words are in `assistant_screen_words.json`; a
// run with `RECORD_WORDS=1` in the environment writes that file, any other
// run compares with it.

const String _agent = AssistantApp.agent;
const _tcp = 'wy/central/downstream/modbus/tcp';
const _sp = 'wy/central/downstream/modbus/tcp/ahu2/sp';
const _mode = 'wy/central/downstream/modbus/tcp/ahu1/mode';
const _http = 'wy/central/downstream/http';
const _s3 = 'wy/central/downstream/s3';
const _plc = 'wy/central/downstream/modbus/tcp/plc1';
const _valve = 'wy/central/downstream/modbus/tcp/plc1/valve';
const _links = 'wy/central/sys/links/agent';

final _record = Platform.environment['RECORD_WORDS'] == '1';
final _file = File('test/assistant_screen_words.json');
final _recorded = <String, List<String>>{};
final Map<String, Object?> _expected = _record || !_file.existsSync()
    ? const {}
    : jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;

/// A plan that waits with each kind of step: a `config` invoke with a
/// warning, the model's words and a fix; a `write` set checked when it
/// runs; a known secret; arguments whose schema is not known; a proof; a
/// change the agent runs with its own key; a sleep. Arguments of each JSON
/// type.
Map<String, Object?> _richPlan({
  String state = 'awaiting_approval',
  Map<int, Map<String, Object?>> results = const {},
  List<String> log = const ['asked by user:olena'],
  Map<String, Object?> extra = const {},
}) => {
  'state': state,
  'owner': 'user:olena',
  'ask': 'add ahu2 and the erp link',
  'plan': [
    {
      'n': 1,
      'invoke': _tcp,
      'action': 'add_device',
      'args': {
        'name': 'ahu2',
        'unit': 3,
        'scale': 0.5,
        'opts': {
          'poll_ms': 500,
          'tags': ['a', 'b'],
        },
      },
      'level': 'config',
      'approval': true,
      'check': 'now',
      'reason': 'the device the operator asked for',
      'warn': 'unit 3 answers already as ahu1',
      'model_warn': 'the name may clash with **ahu2** [old](http://x)',
      'result': ?results[1],
    },
    {
      'n': 2,
      'set': _sp,
      'value': 21.5,
      'level': 'write',
      'after': [1],
      'approval': true,
      'check': 'at_run',
      'result': ?results[2],
    },
    {
      'n': 3,
      'invoke': _http,
      'action': 'add_connection',
      'args': {'name': 'erp', 'password': 'hunter2'},
      'level': 'config',
      'approval': true,
      'check': 'now',
      'result': ?results[3],
    },
    {
      'n': 4,
      'invoke': _s3,
      'action': 'add_connection',
      'args': {'name': 'bucket', 'key': 'AKIA-1'},
      'level': 'config',
      'approval': true,
      'check': 'at_run',
      'result': ?results[4],
    },
    {
      'n': 5,
      'expect': _sp,
      'equals': 21.5,
      'timeout_s': 10.0,
      'level': 'read',
      'after': [2],
      'approval': false,
      'check': 'now',
      'result': ?results[5],
    },
    {
      'n': 6,
      'set': _mode,
      'value': 'auto',
      'level': 'write',
      'approval': false,
      'check': 'now',
      'result': ?results[6],
    },
    {'n': 7, 'sleep_s': 2.5, 'level': 'read', 'result': ?results[7]},
  ],
  'suggestions': [
    {
      'id': 'f1',
      'label': 'Use unit 4',
      'detail': 'unit 4 is free',
      'changes': 1,
      'step': 1,
    },
    {
      'id': 's2',
      'label': 'Ask ivan first',
      'detail': 'Ivan, is unit 3 yours?',
      'changes': 0,
    },
  ],
  'step': 0,
  'log': log,
  'tokens': 12,
  ...extra,
};

const Map<String, Object> _ok = {
  'status': 'ok',
  'message': 'ok',
  'time': 1794100000,
};

/// The schema of step 3's action: `password` is a secret.
void _metas(AssistantApp app) {
  app.api.metas[_http] = NodeMeta(
    actions: {
      'add_connection': ActionMeta(
        params: {
          'name': ParamMeta(),
          'password': ParamMeta(editor: 'password'),
        },
      ),
    },
  );
}

/// The agent's root as *What it may do* reads it.
void _cfg(AssistantApp app, {String mode = 'write'}) {
  app.api
    ..metas[_agent] = NodeMeta(
      cfg: {
        'model': const VStr('claude-sonnet-5-5'),
        'require_approval': VStr(mode),
        'allowed_prefixes': Value.from([
          'wy/central/downstream/modbus',
          'wy/central/storage',
        ]),
        'budget_tokens_day': const VInt(1000000),
        'api_key_ref': const VStr('anthropic_api_key'),
        'api_base': const VStr('https://api.anthropic.com'),
      },
    )
    ..invokes['$_links ▸ secrets'] = [
      Value.from(['anthropic_api_key']),
    ]
    ..invokes['$_links ▸ history'] = [
      Value.from([
        {
          'rev': 2,
          'params': {
            'require_approval': mode,
            'allowed_prefixes': [
              'wy/central/downstream/modbus',
              'wy/central/storage',
            ],
          },
        },
      ]),
    ];
}

/// Every word on screen: the texts, the selectable texts (keys and
/// arguments) and the field contents, then the tooltips (disabled reasons).
/// The words of a chart (its axes follow the clock) are left out.
List<String> _words(WidgetTester t) {
  final chart = t
      .widgetList<RichText>(
        find.descendant(
          of: find.byType(Trend),
          matching: find.byType(RichText),
        ),
      )
      .toSet();
  return [
    for (final w in t.widgetList<RichText>(find.byType(RichText)))
      if (!chart.contains(w)) w.text.toPlainText(),
    for (final w in t.widgetList<EditableText>(find.byType(EditableText)))
      'field: ${w.controller.text}',
    for (final w in t.widgetList<Tooltip>(find.byType(Tooltip)))
      if ((w.message ?? '').isNotEmpty) 'tip: ${w.message}',
  ];
}

/// Compares the words on screen with those recorded for [name].
void _check(WidgetTester t, String name) {
  final got = _words(t);
  if (_record) {
    _recorded[name] = got;
    return;
  }
  expect(_expected[name], isNotNull, reason: 'no words recorded for $name');
  expect(got, (_expected[name]! as List<Object?>).cast<String>(), reason: name);
}

/// The drawer over a plain screen, as Explorer puts it (⌘J).
Future<void> _drawer(WidgetTester tester, AssistantApp app) async {
  app.store.dispatchSync(SetDrawerAction(open: true));
  await tester.pumpWidget(
    StoreProvider<AppState>(
      store: app.store,
      child: MaterialApp(
        theme: darkTheme(),
        localizationsDelegates: const [S.delegate],
        home: const Scaffold(
          body: Row(
            children: [
              Spacer(),
              SizedBox(width: 640, child: AssistantDrawerConnector()),
            ],
          ),
        ),
      ),
    ),
  );
  await app.settle(tester);
}

/// The tab as [AssistantApp.pump] shows it, tall enough that every card is
/// built and every control can be tapped.
Future<void> _pump(
  WidgetTester t,
  AssistantApp app, {
  String? selected,
}) async {
  await app.pump(t, selected: selected);
  t.view.physicalSize = const Size(1364, 5000);
  await t.pump();
}

Finder _tick(int n) => find.byType(Checkbox).at(n - 1);

void main() {
  setUpAll(() => S.load(const Locale('en')));
  tearDownAll(() {
    if (_record) {
      _file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_recorded)}\n',
      );
    }
  });

  group('the words of the tab', () {
    testWidgets('no agent link on the site', (t) async {
      final app = AssistantApp();
      app.api.children_['wy/central/sys/links'] = [];
      await _pump(t, app);
      _check(t, 'no agent');
    });

    testWidgets('an agent without tasks', (t) async {
      final app = AssistantApp();
      await _pump(t, app);
      _check(t, 'no tasks');
    });

    testWidgets('a task that asks back, before and after picks', (t) async {
      final app = AssistantApp()..task('t-1', askRecord());
      await _pump(t, app, selected: 't-1');
      _check(t, 'asks');
      await t.tap(find.text('Slave ID 4'));
      await t.tap(find.text('Fan speed'));
      await t.pump();
      _check(t, 'asks, picked');
    });

    testWidgets('a task whose questions were answered', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          askRecord(
            state: 'planning',
            answers: {
              'q1': ['u3'],
              'q2': 'only the fan',
            },
          ),
        );
      await _pump(t, app, selected: 't-1');
      _check(t, 'answered');
    });

    testWidgets('a plan that waits, then its masked arguments shown, then '
        'a step left out', (t) async {
      final app = AssistantApp()..task('t-1', _richPlan());
      _metas(app);
      await _pump(t, app, selected: 't-1');
      _check(t, 'plan');
      await t.tap(find.text('Show arguments'));
      await t.pump();
      _check(t, 'plan, shown');
      await t.tap(_tick(2));
      await t.pump();
      _check(t, 'plan, step 2 left out');
    });

    testWidgets('a refused approval', (t) async {
      final app = AssistantApp()..task('t-1', planRecord());
      app.api.errors['$_agent/tasks/t-1 ▸ approve'] = WyrmException.of(
        Status.permissionDenied,
        'step 1 needs config on wy/central/downstream/modbus/tcp',
      );
      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Approve 2 changes and run'));
      await app.settle(t);
      _check(t, 'refused');
    });

    testWidgets('a plan of a task the user did not ask', (t) async {
      final app = AssistantApp(
        user: 'ivan',
        grants: const [('wy/central/**', 'write')],
        max: 'write',
      )..task('t-1', planRecord());
      await _pump(t, app, selected: 't-1');
      _check(t, 'stranger');
    });

    testWidgets('a plan another task replaced', (t) async {
      final app = AssistantApp()
        ..task('t-1', {...planRecord(), 'replaced_by': 't-2'});
      await _pump(t, app, selected: 't-1');
      _check(t, 'replaced');
    });

    testWidgets('a run at step 2', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(
            state: 'running',
            step: 2,
            results: const {
              1: {'status': 'ok', 'message': 'added ahu2', 'time': 1794100000},
            },
            log: const ['asked by user:olena', 'approved by user:olena'],
          ),
        );
      await _pump(t, app, selected: 't-1');
      _check(t, 'running');
    });

    testWidgets('a done task: its result, more units, a step left out', (
      t,
    ) async {
      final app = AssistantApp()
        ..task(
          't-1',
          _richPlan(
            state: 'done',
            results: const {
              1: {'status': 'ok', 'message': 'added ahu2', 'time': 1794100000},
              2: {'status': 'ok', 'message': 'ok', 'time': 1794100030},
              3: {'status': 'skipped', 'message': 'skipped by user:olena'},
              4: {'status': 'ok', 'message': '', 'time': 1794100035},
              5: {'status': 'ok', 'message': '21.5', 'time': 1794100041},
              6: _ok,
              7: _ok,
            },
            log: const [
              'asked by user:olena',
              'approved by user:olena, 1 step(s) left out',
            ],
            extra: {
              'suggestions': [
                {
                  'id': 's3',
                  'label': 'Same for more units?',
                  'detail': 'copy the points of ahu2',
                  'changes': 2,
                  'rows': [
                    {'key': '$_tcp/ahu3', 'label': 'ahu3', 'detail': 'unit 5'},
                    {'key': '$_tcp/ahu4', 'label': 'ahu4', 'detail': 'unit 6'},
                  ],
                },
                {
                  'id': 's2',
                  'label': 'Ask ivan first',
                  'detail': 'Ivan, is unit 3 yours?',
                  'changes': 0,
                },
              ],
            },
          ),
        );
      _metas(app);
      await _pump(t, app, selected: 't-1');
      app.store.dispatchSync(
        SetLiveValuesAction({
          _sp: LiveValue(
            value: 21.5,
            time: DateTime.utc(2026, 11, 15, 10),
          ),
        }),
      );
      await t.pump();
      _check(t, 'done');
      await t.tap(find.text('ahu4'));
      await t.pump();
      _check(t, 'done, a row ticked');
    });

    testWidgets('a run that stopped: the review and the ways out', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(
            state: 'failed',
            step: 2,
            results: const {
              1: {'status': 'ok', 'message': 'added ahu2'},
              2: {
                'status': 'failed',
                'message': 'out_of_range: 21.5 is above max 21',
              },
            },
            log: const ['asked by user:olena', 'approved by user:olena'],
          )..addAll({
            'review': 'The point allows at most 21 °C.',
            'suggestions': [
              {
                'id': 's1',
                'label': 'Set 21 instead',
                'detail': 'one step',
                'changes': 1,
              },
              {
                'id': 's2',
                'label': 'Leave it as it is',
                'detail': '',
                'changes': 0,
              },
            ],
          }),
        );
      await _pump(t, app, selected: 't-1');
      _check(t, 'failed');
    });

    testWidgets('a run the model reviews', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(
            state: 'failed',
            step: 2,
            results: const {
              1: {'status': 'ok', 'message': 'added ahu2'},
              2: {'status': 'failed', 'message': 'timeout'},
            },
          )..['reviewing'] = true,
        );
      await _pump(t, app, selected: 't-1');
      _check(t, 'reviewing');
    });

    testWidgets('a task that failed before a plan, with config mode', (
      t,
    ) async {
      final app = AssistantApp()
        ..task('t-1', {
          ...planRecord(state: 'failed'),
          'plan': const <Object?>[],
          'error': 'the model gave up',
          'log': const [
            'asked by user:olena',
            'model: I read the tree.',
            'failed: the model gave up',
          ],
        });
      _cfg(app, mode: 'config');
      await _pump(t, app, selected: 't-1');
      _check(t, 'failed early');
    });

    testWidgets('What it may do, then a mode staged', (t) async {
      final app = AssistantApp();
      _cfg(app);
      await _pump(t, app);
      await t.tap(find.text('What it may do'));
      await app.settle(t);
      app.api.subs['$_agent/budget_used_today']!.add(
        const ValSample(
          '$_agent/budget_used_today',
          Sample(VInt(182000), t: 1),
        ),
      );
      await app.settle(t);
      _check(t, 'rights');
      await t.tap(find.text('Only config steps'));
      await app.settle(t);
      _check(t, 'rights, staged');
    });

    testWidgets('What it may do without config on the link', (t) async {
      final app = AssistantApp(
        grants: const [('wy/central/**', 'write')],
        max: 'write',
      );
      _cfg(app, mode: 'never');
      await _pump(t, app);
      await t.tap(find.text('What it may do'));
      await app.settle(t);
      _check(t, 'rights, no config');
    });
  });

  group('the words of the drawer', () {
    Map<String, Object?> found() => {
      ...planRecord(state: 'done'),
      'plan': const <Object?>[],
      'findings': [
        {'key': _tcp, 'label': 'tcp', 'detail': 'connected'},
        {'key': _plc, 'label': 'plc1', 'detail': '4 of 5 points good'},
        {'key': _valve, 'label': 'valve', 'detail': 'bad since 03:12'},
      ],
      'findings_refused': {'rights_expired': 2, 'limit': 1, 'invalid': 1},
      'suggestions': [
        {
          'id': 's2',
          'label': 'Ask ivan first',
          'detail': 'Ivan, did you move it?',
          'changes': 0,
        },
      ],
    };

    testWidgets('What I found, the timeline and its audit', (t) async {
      final now = DateTime.now().toUtc();
      // 03:05 on this machine's clock, as the audit lines show it
      final edit = DateTime(2026, 11, 15, 3, 5).toUtc();
      final app = AssistantApp()..task('t-1', found());
      app.api
        ..histories[_valve] = [
          for (var i = 0; i < 4; i++)
            HistRow(
              now
                  .subtract(Duration(minutes: 40 - i * 10))
                  .microsecondsSinceEpoch,
              VFloat(11.0 + i),
              Quality.good,
            ),
        ]
        ..invokes['wy/central/sys/audit ▸ tail'] = [
          VArray([
            VMap({
              't': VInt(edit.microsecondsSinceEpoch),
              'op': const VStr('invoke'),
              'key': const VStr('$_valve/~act/edit'),
              'sub': const VStr('user:ivan'),
              'status': const VInt(0),
            }),
            VMap({
              't': VInt(edit.microsecondsSinceEpoch + 1000000),
              'op': const VStr('set'),
              'key': const VStr('$_valve/~set'),
              'sub': const VStr('user:olena'),
              'status': const VInt(0x22),
            }),
          ]),
        ];
      await _pump(t, app, selected: 't-1');
      app.store
        ..dispatchSync(SelectPointAction(_valve))
        ..dispatchSync(
          SetLiveValuesAction({
            _tcp: LiveValue(value: 1, time: now),
            _valve: LiveValue(value: 0, quality: q.Quality.bad, time: now),
          }),
        );
      await _drawer(t, app);
      _check(t, 'drawer, found');
    });

    testWidgets('without config on sys/audit', (t) async {
      final app = AssistantApp(
        grants: const [('wy/central/**', 'write')],
        max: 'write',
      )..task('t-1', found());
      await _pump(t, app, selected: 't-1');
      app.store.dispatchSync(SelectPointAction(_valve));
      await _drawer(t, app);
      _check(t, 'drawer, no audit');
    });

    testWidgets('a plan that waits: the second tile is a draft', (t) async {
      final app = AssistantApp()..task('t-1', _richPlan());
      _metas(app);
      await _pump(t, app, selected: 't-1');
      await _drawer(t, app);
      _check(t, 'drawer, waiting');
    });

    testWidgets('a done task in config mode: the second tile asks', (
      t,
    ) async {
      final app = AssistantApp()
        ..task('t-1', {
          ...planRecord(
            state: 'done',
            results: const {1: _ok, 2: _ok, 3: _ok},
          ),
          'suggestions': [
            {
              'id': 's2',
              'label': 'Ask ivan first',
              'detail': 'Ivan, did you move it?',
              'changes': 1,
            },
          ],
        });
      _cfg(app, mode: 'config');
      await _pump(t, app, selected: 't-1');
      await _drawer(t, app);
      _check(t, 'drawer, done');
    });
  });

  group('what each control sends', () {
    testWidgets('Approve: the ticked steps and the plan on screen', (t) async {
      final app = AssistantApp()..task('t-1', _richPlan());
      _metas(app);
      app.api.invokes['$_agent/tasks/t-1 ▸ approve'] = [];
      await _pump(t, app, selected: 't-1');
      // masked arguments are looked at first
      await t.tap(find.textContaining('Approve'));
      await app.settle(t);
      expect(app.calls('approve'), isEmpty);
      await t.tap(find.text('Show arguments'));
      await t.pump();
      await t.tap(find.textContaining('changes and run'));
      await app.settle(t);
      final call = app.calls('approve').single;
      expect(call.key, '$_agent/tasks/t-1');
      expect(call.args?['steps'], Value.from([1, 2, 3, 4]));
      expect(
        call.args?['plan'],
        VStr(planHash(Value.from(_richPlan()['plan']))!),
      );
    });

    testWidgets('Reject with a reason', (
      t,
    ) async {
      final app = AssistantApp()..task('t-1', planRecord());
      app.api.invokes['$_agent/tasks/t-1 ▸ reject'] = [];
      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'not today');
      await t.tap(find.text('Reject').last);
      await app.settle(t);
      expect(
        app.calls('reject').single.args,
        Value.from({'reason': 'not today'}),
      );
    });

    testWidgets('Cancel with a confirmation', (t) async {
      final run = AssistantApp()
        ..task('t-1', planRecord(state: 'running', step: 1));
      run.api.invokes['$_agent/tasks/t-1 ▸ cancel'] = [];
      await _pump(t, run, selected: 't-1');
      await t.tap(find.text('Cancel task'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel task').last);
      await run.settle(t);
      expect(run.calls('cancel'), hasLength(1));
    });

    testWidgets('Write the plan sends the picks; the box answers in words', (
      t,
    ) async {
      final app = AssistantApp()..task('t-1', askRecord());
      app.api.invokes['$_agent/tasks/t-1 ▸ answer'] = [];
      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Slave ID 4'));
      await t.tap(find.text('Fan speed'));
      await t.tap(find.text('Supply temperature'));
      await t.pump();
      await t.tap(find.text('Write the plan'));
      await app.settle(t);
      expect(
        app.calls('answer').single.args,
        Value.from({
          'answers': {
            'q1': ['u4'],
            'q2': ['supply', 'fan'],
          },
        }),
      );
    });

    testWidgets('an ask follows the task on screen; New task does not', (
      t,
    ) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(state: 'done', results: const {1: _ok, 2: _ok, 3: _ok}),
        );
      app.api.invokes['$_agent ▸ ask'] = [
        Value.from({'task': 't-2', 'state': 'planning'}),
      ];
      await _pump(t, app, selected: 't-1');
      await t.enterText(find.byType(TextField).last, 'and ahu3');
      await t.pump();
      await t.tap(find.text('Ask'));
      await app.settle(t);
      expect(
        app.calls('ask').single.args,
        Value.from({'task': 'and ahu3', 'parent': 't-1'}),
      );
      expect(app.store.state.tasks.selectedTask, 't-2');

      await t.tap(find.text('New task'));
      await t.pump();
      expect(app.store.state.tasks.selectedTask, isNull);
      await t.enterText(find.byType(TextField).last, 'list the links');
      await t.pump();
      await t.tap(find.text('Ask'));
      await app.settle(t);
      expect(
        app.calls('ask').last.args,
        Value.from({'task': 'list the links'}),
      );
    });

    testWidgets('a task picked in the list is read; the panel reads the '
        'secrets; a mode is staged', (t) async {
      final app = AssistantApp()
        ..task('t-1', planRecord())
        ..task('t-2', planRecord(state: 'done'));
      _cfg(app);
      await _pump(t, app);
      final before = app.calls('~state').length;
      await t.tap(find.text('t-2').first);
      await app.settle(t);
      expect(app.calls('~state').length, greaterThan(before));
      expect(app.store.state.tasks.selectedTask, 't-2');

      await t.tap(find.text('What it may do'));
      await app.settle(t);
      expect(app.calls('secrets'), isNotEmpty);
      await t.tap(find.textContaining('Never —'));
      await app.settle(t);
      final staged = app.store.state.changes.table.values.single;
      expect(staged.key, _links);
      expect(
        (staged.args['params']! as Map<String, Object?>)['require_approval'],
        'never',
      );
    });

    testWidgets('a fix, a way out and more units are follow-up asks', (
      t,
    ) async {
      final app = AssistantApp()..task('t-1', _richPlan());
      _metas(app);
      app.api.invokes['$_agent ▸ ask'] = [
        Value.from({'task': 't-2', 'state': 'planning'}),
      ];
      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Use unit 4'));
      await app.settle(t);
      expect(
        app.calls('ask').single.args,
        Value.from({'task': 'Use unit 4. unit 4 is free', 'parent': 't-1'}),
      );
    });

    testWidgets('the drawer: the draft is copied, Open full and the close', (
      t,
    ) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final app = AssistantApp()..task('t-1', _richPlan());
      _metas(app);
      await _pump(t, app, selected: 't-1');
      await _drawer(t, app);
      await t.tap(find.text('Ask ivan first'));
      await t.pumpAndSettle();
      await t.tap(find.text('Copy'));
      await t.pumpAndSettle();
      expect(copied, 'Ivan, is unit 3 yours?');
      expect(app.calls('ask'), isEmpty);

      await t.tap(find.text('New task'));
      await t.pump();
      expect(app.store.state.tasks.selectedTask, isNull);
      expect(app.store.state.assistant.drawer, isTrue);
      await t.tap(find.byTooltip('Close (Cmd+J)'));
      await t.pump();
      expect(app.store.state.assistant.drawer, isFalse);
    });
  });

  group('what each control does on screen', () {
    // one router per test file: the two steps that leave the tab are one
    // test
    testWidgets('Open full closes the drawer; Open in Explorer selects the '
        'node the plan changed', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(state: 'done', results: const {1: _ok, 2: _ok, 3: _ok}),
        );
      await _pump(t, app, selected: 't-1');
      createAppRouter(app.store);
      await _drawer(t, app);
      await t.tap(find.text('Open full'));
      await app.settle(t);
      expect(app.store.state.assistant.drawer, isFalse);
      expect(app.store.state.tasks.selectedTask, 't-1');

      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Open sp in Explorer'));
      await app.settle(t);
      expect(app.store.state.nodes.selectedNode, _sp);
    });

    testWidgets('a way out of a stopped run is a follow-up ask', (t) async {
      final app = AssistantApp()
        ..task(
          't-1',
          planRecord(
              state: 'failed',
              step: 2,
              results: const {
                1: _ok,
                2: {'status': 'failed', 'message': 'timeout'},
              },
            )
            ..['suggestions'] = [
              {
                'id': 's1',
                'label': 'Set 21 instead',
                'detail': 'one step',
                'changes': 1,
              },
            ],
        );
      app.api.invokes['$_agent ▸ ask'] = [
        Value.from({'task': 't-2', 'state': 'planning'}),
      ];
      await _pump(t, app, selected: 't-1');
      await t.tap(find.text('Set 21 instead'));
      await app.settle(t);
      expect(
        app.calls('ask').single.args,
        Value.from({'task': 'Set 21 instead. one step', 'parent': 't-1'}),
      );
    });

    testWidgets('an @ chip is taken away', (t) async {
      final app = AssistantApp();
      await _pump(t, app);
      app.store.dispatchSync(SetChipAction(_tcp));
      await t.pump();
      await t.tap(
        find.descendant(
          of: find.byTooltip(_tcp),
          matching: find.byType(InkWell),
        ),
      );
      await t.pump();
      expect(app.store.state.assistant.chips, isEmpty);
    });

    testWidgets("the timeline's window, and its reset", (t) async {
      final app = AssistantApp()..task('t-1', planRecord(state: 'done'));
      app.api.histories[_valve] = [
        HistRow(
          DateTime.now()
              .subtract(const Duration(minutes: 30))
              .microsecondsSinceEpoch,
          const VFloat(11),
          Quality.good,
        ),
      ];
      await _pump(t, app, selected: 't-1');
      app.store.dispatchSync(SelectPointAction(_valve));
      await _drawer(t, app);
      final trend = t.widget<Trend>(find.byType(Trend)).vm;
      final card = t.widget<FoundCard>(find.byType(FoundCard));
      final mid = (trend.rangeStart + trend.rangeEnd) ~/ 2;
      card.onWindow(mid, trend.rangeEnd);
      await t.pump();
      expect(app.store.state.nodes.historyWindow, isNotNull);
      card.onReset!();
      await t.pump();
      expect(app.store.state.nodes.historyWindow, isNull);
    });
  });
}
