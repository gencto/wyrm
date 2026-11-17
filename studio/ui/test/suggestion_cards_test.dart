import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/blocked.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/theme/common.dart';
import 'package:ui/theme/extensions/colors.dart';

Widget _app(Widget child) => MaterialApp(
  theme: darkTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The cards of what the model offers next (ADR 0049 amendment).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('a tile with a reason is shown and cannot be picked', (
    tester,
  ) async {
    final picked = <String>[];
    await tester.pumpWidget(
      _app(
        StoppedCard(
          vm: const StoppedCardVm(
            step: 2,
            message: 'timeout',
            ways: [
              SuggestionTileVm(id: 'a', label: 'Try unit 4', changes: 1),
              SuggestionTileVm(
                id: 'b',
                label: 'Undo',
                changes: 1,
                blocked: BlockedLacks(NeedsLevel(AccessLevel.write, 'agent')),
              ),
            ],
          ),
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('Try unit 4'));
    await tester.tap(find.text('Undo'));
    expect(picked, ['a']);
    expect(find.byTooltip('needs write on agent'), findsOneWidget);
  });

  testWidgets('the model’s words on a step are not drawn as the link’s '
      'warning', (tester) async {
    await tester.pumpWidget(
      _app(
        const PlanCard(
          vm: PlanCardVm(
            line: PlanChecked(now: 1, atRun: 0),
            badge: .awaitingApproval,
            steps: [
              PlanStepVm(
                n: 1,
                verb: .set,
                node: 'wy/plant/downstream/m/a',
                level: AccessLevel.write,
                warn: 'at the limit',
                modelWarn: 'see [the manual](https://example.org)',
              ),
            ],
          ),
        ),
      ),
    );

    final c = tester.element(find.byType(PlanCard)).colors;
    Color? ground(String text) {
      final box = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text(text),
              matching: find.byType(Container),
            ),
          )
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .first;
      return box.color;
    }

    expect(ground('at the limit'), c.warnTint);
    expect(
      ground('see [the manual](https://example.org)'),
      isNot(c.warnTint),
    );
    // the model's text stays text: no link is made of it
    expect(find.text('the manual'), findsNothing);
  });
}
