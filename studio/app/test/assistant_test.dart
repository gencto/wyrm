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

  testWidgets(
    'a task of a downstream site: Approve is locked with the reason',
    (
      tester,
    ) async {
      final app = AssistantApp()..task('t-1', planRecord());
      await app.pump(tester, selected: 't-1');

      app.store.dispatchSync(ViewSiteAction('plant'));
      await tester.runAsync(
        () => app.store.dispatchAndWait(RetrieveTaskRecordAction('t-1')),
      );
      await app.settle(tester);

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
    },
  );

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
