import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

ChoicesCardVm _card(WidgetTester tester) =>
    tester.widget<ChoicesCard>(find.byType(ChoicesCard)).vm;

List<String> _picked(WidgetTester tester) => [
  for (final q in _card(tester).questions)
    for (final o in q.options)
      if (o.picked) o.id,
];

Button _button(WidgetTester tester, String label) =>
    tester.widget<Button>(find.widgetWithText(Button, label));

/// Board *AssistantAsk* (spec `assistant.md` §2 step 4): the assistant asks
/// back; the person answers from the card or in their own words.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const task = '${AssistantApp.agent}/tasks/t-1';

  testWidgets('a task that waits for an answer shows the card and the state', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', askRecord());
    await app.pump(tester, selected: 't-1');

    // the state is in the pill and in the list
    expect(
      tester.widget<StatusPill>(find.byType(StatusPill).first).vm.label,
      'awaiting your answer',
    );
    expect(find.text('awaiting your answer'), findsWidgets);
    expect(find.text('Which unit is AHU 2?'), findsOneWidget);
    expect(find.text('Slave ID 4'), findsOneWidget);
    expect(find.text('answers, no name'), findsOneWidget);
    // nothing picked: Write the plan says what to do
    final write = _button(tester, 'Write the plan');
    expect(write.onPressed, isNull);
    expect(write.disabledReason, contains('Pick an option'));
    // the box answers, it does not ask a new task
    expect(find.text('Answer'), findsOneWidget);
  });

  testWidgets('one option of a question, several of a multiple one', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', askRecord());
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Slave ID 3'));
    await tester.pump();
    await tester.tap(find.text('Slave ID 4'));
    await tester.pump();
    expect(_picked(tester), ['u4']);

    await tester.tap(find.text('Fan speed'));
    await tester.pump();
    await tester.tap(find.text('Supply temperature'));
    await tester.pump();
    expect(_picked(tester), ['u4', 'supply', 'fan']);

    // a second tap takes the pick back
    await tester.tap(find.text('Fan speed'));
    await tester.pump();
    expect(_picked(tester), ['u4', 'supply']);
  });

  testWidgets('Write the plan sends the picks by question id', (tester) async {
    final app = AssistantApp()..task('t-1', askRecord());
    app.api.invokes['$task ▸ answer'] = [
      Value.from({'task': 't-1', 'state': 'planning'}),
      Value.from({'task': 't-1', 'event': 'text', 'text': 'Unit 4 it is.'}),
      Value.from({
        'task': 't-1',
        'event': 'state',
        'text': 'awaiting_approval',
      }),
    ];
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Slave ID 4'));
    await tester.pump();
    await tester.tap(find.text('Fan speed'));
    await tester.pump();
    await tester.tap(find.text('Supply temperature'));
    await tester.pump();
    // the record after the answer
    app.api.docs['$task ~state'] = Value.from(
      askRecord(
        state: 'awaiting_approval',
        answers: const {
          'q1': ['u4'],
          'q2': ['supply', 'fan'],
        },
      ),
    );
    await tester.tap(find.text('Write the plan'));
    await app.settle(tester);

    final call = app.calls('answer').single;
    expect(call.key, task);
    expect(
      call.args,
      Value.from({
        'answers': {
          'q1': ['u4'],
          'q2': ['supply', 'fan'],
        },
      }),
    );
    // the model's line arrived on the answer's stream
    expect(find.text('Unit 4 it is.'), findsOneWidget);
    // the card folds into one line per question
    expect(find.text('from the card: Slave ID 4'), findsWidgets);
    expect(
      find.text('from the card: Supply temperature, Fan speed'),
      findsOneWidget,
    );
    expect(find.text('Write the plan'), findsNothing);
    expect(find.text('Slave ID 3'), findsNothing);
    expect(app.store.state.assistant.picks, isEmpty);
  });

  testWidgets('typing in the box answers the card in the person’s words', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', askRecord());
    app.api.invokes['$task ▸ answer'] = [
      Value.from({'task': 't-1', 'state': 'planning'}),
    ];
    await app.pump(tester, selected: 't-1');
    app.api.docs['$task ~state'] = Value.from(
      askRecord(
        state: 'planning',
        answers: const {'q1': 'unit 4, I checked', 'q2': 'unit 4, I checked'},
      ),
    );

    await tester.enterText(find.byType(TextField), 'unit 4, I checked');
    await tester.pump();
    expect(_button(tester, 'Answer').onPressed, isNotNull);
    await tester.tap(find.text('Answer'));
    await app.settle(tester);

    expect(app.calls('ask'), isEmpty);
    expect(
      app.calls('answer').single.args,
      Value.from({'text': 'unit 4, I checked'}),
    );
    expect(app.store.state.assistant.draft, isNull);
    expect(
      find.text('in your own words: unit 4, I checked'),
      findsNWidgets(2),
    );
  });

  testWidgets('a refused answer is an error and the record is read again', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', askRecord());
    app.api.errors['$task ▸ answer'] = WyrmException.of(
      Status.invalidParameter,
      'task is failed, not awaiting_answer',
    );
    await app.pump(tester, selected: 't-1');
    app.api.docs['$task ~state'] = Value.from(
      askRecord(state: 'failed')..['error'] = 'interrupted by restart',
    );

    await tester.tap(find.text('Slave ID 4'));
    await tester.pump();
    await tester.tap(find.text('Write the plan'));
    await app.settle(tester);

    // the task is shown as the record has it now
    expect(find.text('interrupted by restart'), findsOneWidget);
    expect(find.text('Write the plan'), findsNothing);
  });
}
