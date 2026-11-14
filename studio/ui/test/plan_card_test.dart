import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/theme/common.dart';

Widget _card(List<PlanStepVm> steps) => MaterialApp(
  theme: darkTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PlanCard(
        vm: PlanCardVm(title: 'Plan', state: 'awaiting approval', steps: steps),
      ),
    ),
  ),
);

/// Board *Assistant*: a step of a plan as the person reads it.
void main() {
  testWidgets('the check line has an icon of the set, not a glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(const [
        PlanStepVm(
          n: 1,
          verb: 'INVOKE',
          target: 'wy/plant/downstream/modbus/tcp',
          level: 'config',
          check: 'checked against the live tree',
        ),
        PlanStepVm(
          n: 2,
          verb: 'SET',
          target: 'wy/plant/downstream/modbus/tcp/a',
          level: 'write',
          check: 'checked when it runs',
          checked: false,
        ),
      ]),
    );

    expect(
      [
        for (final i in tester.widgetList<AppIcon>(find.byType(AppIcon)))
          i.name,
      ],
      ['ui_check', 'action_hist'],
    );
    // the words alone, no mark typed into the text
    expect(find.text('checked against the live tree'), findsOneWidget);
    expect(find.text('checked when it runs'), findsOneWidget);
    expect(find.textContaining('◷'), findsNothing);
    expect(find.textContaining('✓'), findsNothing);
  });

  testWidgets('the line about secret arguments is under the arguments', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(const [
        PlanStepVm(
          n: 1,
          verb: 'INVOKE',
          target: 'wy/plant/downstream/http',
          level: 'config',
          args: [('name', 'erp'), ('password', '••••••')],
          argsNote: 'A secret argument is not shown.',
        ),
      ]),
    );

    expect(find.text('••••••'), findsOneWidget);
    expect(find.text('A secret argument is not shown.'), findsOneWidget);
  });
}
