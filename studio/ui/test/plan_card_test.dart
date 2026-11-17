import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/theme/common.dart';

Widget _card(List<PlanStepVm> steps) => MaterialApp(
  theme: darkTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PlanCard(
        vm: PlanCardVm(
          line: const PlanChecked(now: 1, atRun: 1),
          badge: .awaitingApproval,
          steps: steps,
        ),
      ),
    ),
  ),
);

/// Board *Assistant*: a step of a plan as the person reads it.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('the check line has an icon of the set, not a glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(const [
        PlanStepVm(
          n: 1,
          verb: .invoke,
          node: 'wy/plant/downstream/modbus/tcp',
          level: AccessLevel.config,
          check: .now,
        ),
        PlanStepVm(
          n: 2,
          verb: .set,
          node: 'wy/plant/downstream/modbus/tcp/a',
          level: AccessLevel.write,
          check: .atRun,
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
    expect(
      find.text('checked when it runs: an earlier step makes this node'),
      findsOneWidget,
    );
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
          verb: .invoke,
          node: 'wy/plant/downstream/http',
          level: AccessLevel.config,
          args: [StepArgVm.shown('name', 'erp'), StepArgVm.masked('password')],
          argsNote: .secret,
        ),
      ]),
    );

    expect(find.text('••••••'), findsOneWidget);
    expect(
      find.textContaining('A secret argument is not shown.'),
      findsOneWidget,
    );
  });
}
