import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/buttons/button.dart';
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

/// Board *Assistant*, a plan that waits (spec `assistant.md` §2 step 2):
/// ticks, the count in Approve, the approval through the gateway, its
/// refusal, Reject with a reason.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const task = '${AssistantApp.agent}/tasks/t-1';

  testWidgets('Approve counts the ticked steps and sends them', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    // two steps need the person; the proof step has no tick
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(_button(tester, 'Approve').label, 'Approve 2 changes and run');
    expect(_button(tester, 'Approve').onPressed, isNotNull);
    expect(
      find.textContaining('Signs one token per ticked step with your rights'),
      findsOneWidget,
    );
    expect(find.textContaining('(engineer)'), findsOneWidget);

    await tester.tap(find.text('Approve 2 changes and run'));
    await app.settle(tester);

    final call = app.calls('approve').single;
    expect(call.key, task);
    expect(_steps(call), [1, 2]);
    expect(call.args?['plan'], isA<VStr>());
  });

  testWidgets('a change that needs no person runs with the agent key: no '
      'tick, counted, and said so', (tester) async {
    // `require_approval: config`: two write sets of the asker need nobody
    final app = AssistantApp()
      ..task('t-1', {
        'state': 'awaiting_approval',
        'owner': 'user:olena',
        'ask': 'set two points, add a device',
        'plan': [
          {
            'n': 1,
            'set': 'wy/central/downstream/modbus/tcp/ahu1/sp',
            'value': 21,
            'level': 'write',
            'approval': false,
            'check': 'now',
          },
          {
            'n': 2,
            'set': 'wy/central/downstream/modbus/tcp/ahu1/mode',
            'value': 'auto',
            'level': 'write',
            'approval': false,
            'check': 'now',
          },
          {
            'n': 3,
            'invoke': 'wy/central/downstream/modbus/tcp',
            'action': 'add_device',
            'args': {'name': 'ahu2'},
            'level': 'config',
            'approval': true,
            'check': 'now',
          },
        ],
        'log': ['asked by user:olena'],
      });
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    expect(find.byType(Checkbox), findsOneWidget);
    expect(
      find.text(
        "runs with the agent's key: this mode needs no person for it, and "
        'it cannot be left out',
      ),
      findsNWidgets(2),
    );
    // all three run once approved
    expect(_button(tester, 'Approve').label, 'Approve 3 changes and run');
    expect(
      find.textContaining(
        "2 steps without a tick change something and run with the agent's "
        'own key',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Approve 3 changes and run'));
    await app.settle(tester);
    // only the ticked step takes a token; the link runs the others
    expect(_steps(app.calls('approve').single), [3]);
  });

  testWidgets('a secret argument is not shown', (tester) async {
    final app = AssistantApp()
      ..task('t-1', {
        'state': 'awaiting_approval',
        'owner': 'user:olena',
        'ask': 'add the erp connection',
        'plan': [
          {
            'n': 1,
            'invoke': 'wy/central/downstream/http',
            'action': 'add_connection',
            'args': {'name': 'erp', 'password': 'hunter2'},
            'level': 'config',
            'approval': true,
            'check': 'now',
          },
        ],
        'log': ['asked by user:olena'],
      });
    app.api.metas['wy/central/downstream/http'] = NodeMeta(
      actions: {
        'add_connection': ActionMeta(
          params: {
            'name': ParamMeta(),
            'password': ParamMeta(editor: 'password'),
          },
        ),
      },
    );
    await app.pump(tester, selected: 't-1');

    expect(find.text('erp'), findsOneWidget);
    expect(find.text('hunter2'), findsNothing);
    expect(find.text('••••••'), findsOneWidget);
    expect(
      find.textContaining('A secret argument is not shown'),
      findsOneWidget,
    );
  });

  testWidgets('an unticked step is left out, with the steps that need it', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.invokes['$task ▸ approve'] = [];
    await app.pump(tester, selected: 't-1');

    await tester.tap(_tick(2));
    await tester.pump();
    expect(_button(tester, 'Approve').label, 'Approve 1 change and run');
    expect(find.text('left out: it will not run'), findsOneWidget);
    // the proof step after it
    expect(find.text('skipped: needs step 2'), findsOneWidget);

    await tester.tap(find.text('Approve 1 change and run'));
    await app.settle(tester);
    expect(_steps(app.calls('approve').single), [1]);
  });

  testWidgets('unticking a step unticks and locks its dependants', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    await app.pump(tester, selected: 't-1');

    await tester.tap(_tick(1));
    await tester.pump();

    final second = tester.widget<Checkbox>(_tick(2));
    expect(second.value, isFalse);
    expect(second.onChanged, isNull);
    expect(find.text('skipped: needs step 1'), findsOneWidget);
    // nothing is ticked: Approve is disabled and says why
    final approve = _button(tester, 'Approve');
    expect(approve.onPressed, isNull);
    expect(approve.disabledReason, 'Tick at least one step.');
    expect(app.calls('approve'), isEmpty);
  });

  testWidgets('a step outside the user’s grants is locked with the reason', (
    tester,
  ) async {
    final app = AssistantApp(
      grants: const [('wy/central/**', 'write')],
    )..task('t-1', planRecord());
    await app.pump(tester, selected: 't-1');

    final first = tester.widget<Checkbox>(_tick(1));
    expect(first.value, isFalse);
    expect(first.onChanged, isNull);
    expect(
      find.byTooltip('needs config on downstream/modbus/tcp/~act/add_device'),
      findsOneWidget,
    );
    expect(_button(tester, 'Approve').onPressed, isNull);
  });

  testWidgets('a refused approval is shown; the task still waits', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    const why =
        'step 2 may be sent 290 s after this approval (the waits before it), '
        'and its approval is good for 300 s: leave it out and ask for it as '
        'a follow-up when this plan is done';
    app.api.errors['$task ▸ approve'] = WyrmException.of(
      Status.invalidParameter,
      why,
    );
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Approve 2 changes and run'));
    await app.settle(tester);

    expect(find.textContaining(why), findsOneWidget);
    expect(find.textContaining('the task still waits'), findsOneWidget);
    expect(find.textContaining('as a follow-up'), findsWidgets);
    // no error dialog, the plan and its ticks are still there
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(PlanCard), findsOneWidget);
    expect(_button(tester, 'Approve').onPressed, isNotNull);

    // the person leaves the step out: the refusal goes, the rest is sent
    app.api.errors.remove('$task ▸ approve');
    app.api.invokes['$task ▸ approve'] = [];
    await tester.tap(_tick(2));
    await tester.pump();
    expect(find.textContaining(why), findsNothing);
    await tester.tap(find.text('Approve 1 change and run'));
    await app.settle(tester);
    expect(_steps(app.calls('approve').last), [1]);
  });

  testWidgets('another site shows its own agent; its task is not approved '
      'here', (tester) async {
    const plant = 'wy/plant/downstream/agent';
    final app = AssistantApp()..task('t-1', planRecord());
    app.api
      ..children_['wy/plant/sys/links'] = [Child('agent', NodeMeta())]
      ..metas['wy/plant/sys/links/agent'] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas[plant] = NodeMeta()
      ..children_['$plant/tasks'] = [Child('t-9', NodeMeta())]
      ..docs['$plant/tasks/t-9 ~state'] = Value.from(
        planRecord()..['ask'] = 'tune ahu7',
      );
    await app.pump(tester, selected: 't-1');
    expect(find.byType(PlanCard), findsOneWidget);

    app.store.dispatchSync(ViewSiteAction('plant'));
    await app.settle(tester);

    // central's task, its plan and its ticks are gone with central
    expect(app.store.state.tasks.table.keys, ['t-9']);
    expect(app.store.state.assistant.agent, plant);
    expect(find.text('add ahu2'), findsNothing);
    expect(find.byType(PlanCard), findsNothing);

    // its record is read when it is opened
    await tester.tap(find.text('t-9').first);
    await app.settle(tester);
    expect(find.text('tune ahu7'), findsWidgets);

    final approve = _button(tester, 'Approve');
    expect(approve.onPressed, isNull);
    expect(approve.disabledReason, contains('This task is on site plant'));
    expect(
      find.textContaining(
        'This gateway signs approvals only for tasks of its own site',
      ),
      findsOneWidget,
    );
    // the plan is only shown
    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('back on its own site, a task of the other site is gone', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.children_['wy/plant/sys/links'] = [];
    await app.pump(tester, selected: 't-1');
    await tester.tap(_tick(2));
    await tester.pump();

    // a read of central's record is still on its way when plant is viewed
    app.api.delays['${AssistantApp.agent}/tasks/t-1 ~state'] = const Duration(
      milliseconds: 200,
    );
    final late = app.store.dispatchAndWait(RetrieveTaskRecordAction('t-1'));
    await tester.pump();
    expect(app.api.calls.where((c) => c.op == 'doc'), hasLength(2));
    app.store.dispatchSync(ViewSiteAction('plant'));
    await app.settle(tester);
    await tester.runAsync(() => late);
    await app.settle(tester);

    // it does not put central's task back, nor do its ticks stay
    expect(app.store.state.tasks.table, isEmpty);
    expect(app.store.state.assistant.unticked, isEmpty);
    expect(find.byType(PlanCard), findsNothing);
  });

  testWidgets('Reject asks for a reason and sends it', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.invokes['$task ▸ reject'] = [];
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reject the plan?'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'unit 3 is ahu-old',
    );
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Reject')),
    );
    await tester.pumpAndSettle();
    await app.settle(tester);

    expect(
      app.calls('reject').single.args?['reason'],
      const VStr('unit 3 is ahu-old'),
    );
  });

  testWidgets('Cancel in the reason dialog rejects nothing', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(app.calls('reject'), isEmpty);
  });

  testWidgets('a done task with steps left out offers the follow-up', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          results: const {
            1: {'status': 'ok', 'message': 'ok'},
            2: {'status': 'skipped', 'message': 'skipped by user:olena'},
            3: {'status': 'skipped', 'message': 'skipped: needs step 2'},
          },
          log: const [
            'asked by user:olena',
            'approved by user:olena, 1 step(s) left out',
          ],
        ),
      );
    app.api.invokes['${AssistantApp.agent} ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');

    expect(
      find.text('approved by olena, 1 step(s) left out'),
      findsOneWidget,
    );
    expect(find.textContaining('Steps left out: 2, 3'), findsOneWidget);

    await tester.tap(find.text('Ask for the steps left out'));
    await app.settle(tester);

    final ask = app.calls('ask').single;
    expect(ask.args?['parent'], const VStr('t-1'));
    expect((ask.args!['task']! as VStr).v, contains('2, 3'));
  });
}
