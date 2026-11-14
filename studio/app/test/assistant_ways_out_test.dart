import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/tasks/actions/add_tasks_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/model_words.dart';
import 'package:ui/assistant/more_rows_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/indicators/arc_spinner.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

Button _button(WidgetTester tester, Pattern label) => tester.widget<Button>(
  find.byWidgetPredicate(
    (w) => w is Button && label.allMatches(w.label).isNotEmpty,
  ),
);

Finder _tick(int n) => find.byType(Checkbox).at(n - 1);

List<int> _steps(Call approve) => [
  for (final n in (approve.args!['steps']! as VArray).v) (n as VInt).v,
];

const String _agent = AssistantApp.agent;
const _ahu3 = 'wy/central/downstream/modbus/tcp/ahu3';
const _ahu4 = 'wy/central/downstream/modbus/tcp/ahu4';

/// The suggestions of the ADR 0049 amendment: a fix for step 1, a way out
/// that changes nothing, and the same for more units.
const Map<String, Object> _fix = {
  'id': 's1',
  'label': 'Try Slave ID 4',
  'detail': 'edit ahu2, then the same check',
  'changes': 1,
  'step': 1,
};
const Map<String, Object> _leave = {
  'id': 's2',
  'label': 'Leave it as it is',
  'detail': 'ahu2 stays, recorded, with bad quality',
  'changes': 0,
};
const Map<String, Object> _more = {
  'id': 's3',
  'label': 'Same for more units?',
  'detail': 'copy the points of ahu2',
  'changes': 2,
  'rows': [
    {'key': _ahu3, 'label': 'ahu3', 'detail': 'unit 5'},
    {'key': _ahu4, 'label': 'ahu4', 'detail': 'unit 6'},
  ],
};

Map<String, Object?> _failed({
  List<Object?> suggestions = const [_fix, _leave],
  bool reviewing = false,
}) =>
    planRecord(
      state: 'failed',
      step: 2,
      results: const {
        1: {'status': 'ok', 'message': 'added ahu2', 'time': 1794108765},
        2: {
          'status': 'failed',
          'message': 'timeout: no answer in 10 s',
          'time': 1794108770,
        },
      },
    )..addAll({
      'error': 'step 2 (set …/sp): timeout',
      'suggestions': suggestions,
      if (reviewing) 'reviewing': true,
      if (!reviewing) 'review': 'Unit 3 does not answer behind this gateway.',
    });

/// Spec `assistant.md` §2 step 5 and the review of steps 1–4: what the
/// model offers next (fixes, ways out, more units), a replaced plan, the
/// composer's chips and hints, the arguments whose schema is not known, and
/// the session's `max`.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const task = '$_agent/tasks/t-1';

  testWidgets('Approve sends the hash of the plan on screen and the steps '
      'ticked there (review finding 7)', (tester) async {
    final record = planRecord();
    final app = AssistantApp()..task('t-1', record);
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    await tester.tap(_tick(2));
    await tester.pump();
    await tester.tap(find.text('Approve 1 change and run'));
    await app.settle(tester);

    final call = app.calls('approve').single;
    expect(call.args?['plan'], VStr(planHash(Value.from(record)['plan'])!));
    expect(_steps(call), [1]);
  });

  testWidgets('a plan that moved after it was drawn is not approved from '
      'the old screen', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    // the store moves, the screen is not drawn again before the press
    final t = app.store.state.tasks.table['t-1']!;
    app.store.dispatchSync(
      AddTasksAction([t.copyWith(planHash: 'another plan')].lock),
    );
    await tester.tap(find.text('Approve 2 changes and run'));
    await app.settle(tester);

    expect(app.calls('approve'), isEmpty);
    expect(find.textContaining('the plan or its ticks changed'), findsOne);
  });

  testWidgets('a fix on a step: the model says it apart from the link, and '
      'the tile replaces the plan', (tester) async {
    final record = planRecord()..['suggestions'] = [_fix, _leave];
    final plan = [...(record['plan']! as List<Object?>)];
    plan[0] = {
      ...(plan[0]! as Map<String, Object?>),
      'warn': 'unit 3 answers with exception 0x0B',
      'model_warn': 'ahu-old used unit 3 before',
    };
    record['plan'] = plan;
    final app = AssistantApp()..task('t-1', record);
    app.api.invokes['$_agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');

    // the link's finding on the warning tint, the model's words as its own
    expect(find.text('unit 3 answers with exception 0x0B'), findsOneWidget);
    final words = tester.widget<ModelWords>(find.byType(ModelWords));
    expect(words.vm.label, 'the assistant says');
    expect(words.vm.text, 'ahu-old used unit 3 before');
    // only the fix of step 1 is on the plan, and it says what it does
    final tile = tester.widget<SuggestionTile>(find.byType(SuggestionTile));
    expect(tile.vm.label, 'Try Slave ID 4');
    expect(tile.vm.note, 'replaces this plan');
    expect(tile.vm.tag, '1 change · its guess');

    await tester.tap(find.text('Try Slave ID 4'));
    await app.settle(tester);
    final ask = app.calls('ask').single;
    expect(
      ask.args,
      Value.from({
        'task': 'Try Slave ID 4. edit ahu2, then the same check',
        'parent': 't-1',
      }),
    );
  });

  testWidgets('a stopped run: the review as the model’s words and the ways '
      'out, each a follow-up ask', (tester) async {
    final app = AssistantApp()..task('t-1', _failed());
    app.api.invokes['$_agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');

    final card = tester.widget<StoppedCard>(find.byType(StoppedCard)).vm;
    expect(card.title, 'Stopped at step 2 · timeout');
    expect(card.review?.text, 'Unit 3 does not answer behind this gateway.');
    expect(card.review?.label, 'what the assistant read about it');
    expect(card.reviewing, isNull);
    // every suggestion of a failed task, the fix of step 1 too; the tag is
    // the model's guess, also at 0
    expect(
      [for (final w in card.ways) (w.label, w.tag, w.note)],
      [
        ('Try Slave ID 4', '1 change · its guess', null),
        ('Leave it as it is', 'nothing · its guess', null),
      ],
    );
    expect(card.caution, isNull);

    await tester.tap(find.text('Leave it as it is'));
    await app.settle(tester);
    expect(
      app.calls('ask').single.args?['parent'],
      const VStr('t-1'),
    );
    expect(app.store.state.tasks.selectedTask, 't-2');
  });

  testWidgets('while the model reviews the run: a spinner, and Cancel', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task('t-1', _failed(suggestions: const [], reviewing: true));
    await app.pump(tester, selected: 't-1');

    final card = tester.widget<StoppedCard>(find.byType(StoppedCard)).vm;
    expect(card.reviewing, 'The assistant reads why it stopped…');
    expect(card.review, isNull);
    expect(find.byType(ArcSpinner), findsOneWidget);
    expect(_button(tester, 'Cancel task').onPressed, isNotNull);
  });

  testWidgets('with require_approval config the ways out say a pick may '
      'write without a person', (tester) async {
    final app = AssistantApp()..task('t-1', _failed());
    app.api.metas[_agent] = NodeMeta(
      cfg: {'require_approval': const VStr('config')},
    );
    await app.pump(tester, selected: 't-1');

    final card = tester.widget<StoppedCard>(find.byType(StoppedCard)).vm;
    expect(card.caution, contains('without a person'));
    expect(card.caution, contains('guess, not a check'));

    // a fix on a plan that waits says it too
    app.task('t-2', planRecord()..['suggestions'] = [_fix]);
    app.store.dispatchSync(SetSelectedTaskAction('t-2'));
    await tester.runAsync(
      () => app.store.dispatchAndWait(RetrieveTaskRecordAction('t-2')),
    );
    await app.settle(tester);
    expect(
      tester.widget<SuggestionTile>(find.byType(SuggestionTile)).vm.note,
      contains('run without a person'),
    );
  });

  testWidgets('a stranger to the task cannot pick its ways out', (
    tester,
  ) async {
    final app = AssistantApp(
      user: 'ivan',
      grants: const [('wy/central/**', 'write')],
      max: 'write',
    )..task('t-1', _failed());
    await app.pump(tester, selected: 't-1');

    final card = tester.widget<StoppedCard>(find.byType(StoppedCard)).vm;
    const reason =
        'only the asker of this task, or config on the agent link, can '
        'follow it up';
    expect(card.ways.map((w) => w.disabledReason), [reason, reason]);
  });

  testWidgets('Same for more units: ticked rows go as context; none ticked, '
      'no plan', (tester) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {
            1: {'status': 'ok', 'message': 'added ahu2'},
            2: {'status': 'ok', 'message': 'ok'},
            3: {'status': 'ok', 'message': '21.5'},
          },
        )..['suggestions'] = [_fix, _more],
      );
    app.api.invokes['$_agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');

    // a done task: no fix tiles, only the suggestion with rows
    expect(find.byType(SuggestionTile), findsNothing);
    expect(find.byType(MoreRowsCard), findsOneWidget);
    expect(_button(tester, 'Make a plan').onPressed, isNull);
    expect(
      _button(tester, 'Make a plan').disabledReason,
      'Tick the nodes the plan is for.',
    );

    await tester.tap(find.text('ahu4'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(_button(tester, 'Make a plan').label, 'Make a plan for 1 unit');
    await tester.tap(find.text('Make a plan for 1 unit'));
    await app.settle(tester);

    expect(
      app.calls('ask').single.args,
      Value.from({
        'task': 'Same for more units?. copy the points of ahu2\nFor: ahu4',
        'parent': 't-1',
        'context': [_ahu4],
      }),
    );
  });

  testWidgets('a replaced plan is shown as replaced: no Approve, the way '
      'to the new task', (tester) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(state: 'failed')
          ..addAll({'replaced_by': 't-2', 'error': 'replaced by t-2'}),
      )
      ..task('t-2', planRecord());
    await app.pump(tester, selected: 't-1');

    expect(
      find.byWidgetPredicate(
        (w) => w is Button && w.label.startsWith('Approve'),
      ),
      findsNothing,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('replaced by tasks/t-2'), findsOneWidget);
    expect(
      find.textContaining('replaced by tasks/t-2 and cannot be approved'),
      findsOneWidget,
    );
    expect(find.text('replaced by t-2'), findsWidgets);

    await tester.tap(find.text('Open tasks/t-2'));
    await app.settle(tester);
    expect(app.store.state.tasks.selectedTask, 't-2');
    expect(find.text('Approve 2 changes and run'), findsOneWidget);
  });

  testWidgets('a step whose schema is not known masks its arguments until '
      'shown', (tester) async {
    final app = AssistantApp()
      ..task('t-1', {
        'state': 'awaiting_approval',
        'owner': 'user:olena',
        'ask': 'set the erp secret',
        'plan': [
          {
            'n': 1,
            'invoke': 'wy/central/downstream/http/erp',
            'action': 'set_secret',
            'args': {'name': 'erp', 'value': 'hunter2'},
            'level': 'config',
            'approval': true,
            'check': 'at_run',
          },
        ],
        'log': ['asked by user:olena'],
      });
    await app.pump(tester, selected: 't-1');

    expect(find.text('hunter2'), findsNothing);
    expect(find.text('••••••'), findsNWidgets(2));
    expect(
      find.textContaining('The schema of this step is not known'),
      findsOne,
    );

    await tester.tap(find.text('Show arguments'));
    await tester.pump();
    expect(find.text('hunter2'), findsOneWidget);
    await tester.tap(find.text('Hide arguments'));
    await tester.pump();
    expect(find.text('hunter2'), findsNothing);
  });

  testWidgets('the composer: a hint per state, a message to a plan that '
      'waits replaces it, chips from Explorer go as context', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.invokes['$_agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');

    expect(find.textContaining('Ask to change the plan'), findsOneWidget);
    const replaces =
        'Sending asks for a new plan: this plan is replaced and can no '
        'longer be approved.';
    expect(find.text(replaces), findsOneWidget);
    // as Explorer does: the change reaches the tab on the next frame
    app.store.dispatchSync(SelectNodeAction(_ahu3));
    await tester.pump();
    await tester.pump();
    // the key picker offers the Explorer selection first
    await tester.tap(find.text('+ from Explorer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('selected in Explorer'));
    await tester.pumpAndSettle();
    expect(find.text('@ modbus/tcp/ahu3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'skip step 2');
    await tester.pump();
    // the hint is gone once typing starts; the warning stays
    expect(find.text(replaces), findsOneWidget);
    await tester.tap(find.text('Ask'));
    await app.settle(tester);

    expect(
      app.calls('ask').single.args,
      Value.from({
        'task': 'skip step 2',
        'parent': 't-1',
        'context': [_ahu3],
      }),
    );
    expect(find.text('@ modbus/tcp/ahu3'), findsNothing);
  });

  testWidgets('a stranger to a plan that waits: no replace hint, the ask is '
      'a task of its own (review, low)', (tester) async {
    final app = AssistantApp(
      user: 'ivan',
      grants: const [('wy/central/**', 'write')],
      max: 'write',
    )..task('t-1', planRecord());
    await app.pump(tester, selected: 't-1');

    expect(find.textContaining('Ask to change the plan'), findsNothing);
    expect(find.textContaining('this plan is replaced'), findsNothing);
  });

  testWidgets('a way out with rows is not a dead tile on the Stopped card '
      '(review, low)', (tester) async {
    final app = AssistantApp()
      ..task('t-1', _failed(suggestions: const [_leave, _more]));
    await app.pump(tester, selected: 't-1');

    final card = tester.widget<StoppedCard>(find.byType(StoppedCard)).vm;
    expect(card.ways.map((w) => w.id), ['s2']);
  });

  testWidgets('Approve waits until the masked arguments of a step are shown '
      '(review, ADR 0029)', (tester) async {
    final app = AssistantApp()
      ..task('t-1', {
        'state': 'awaiting_approval',
        'owner': 'user:olena',
        'ask': 'set the erp secret',
        'plan': [
          {
            'n': 1,
            'invoke': 'wy/central/downstream/http/erp',
            'action': 'set_secret',
            'args': {'name': 'erp', 'value': 'hunter2'},
            'level': 'config',
            'approval': true,
            'check': 'at_run',
          },
        ],
        'log': ['asked by user:olena'],
      });
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    final locked = _button(tester, 'Approve');
    expect(locked.onPressed, isNull);
    expect(
      locked.disabledReason,
      'Show the arguments of step 1 first: its schema is not known, so they '
      'are masked.',
    );

    await tester.tap(find.text('Show arguments'));
    await tester.pump();
    expect(_button(tester, 'Approve').onPressed, isNotNull);
    await tester.tap(find.text('Approve 1 change and run'));
    await app.settle(tester);
    expect(_steps(app.calls('approve').single), [1]);
  });
}
