import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/theme/common.dart';

import '../frames/broker_update.dart';
import '../frames/harness.dart';

/// Boards `BrokerUpdate`, `BrokerUpdateRestart`, `BrokerUpdateDone`,
/// `BrokerUpdateRolledBack` and `BrokerUpdateExternal` (ADR 0048 §2), one
/// golden each, fed by fixture view-models: the broker part is not built
/// and every entry point of these screens is behind a flag that is off.
/// The restart is paused 300 ms into its spinner. The review also in the
/// light theme.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1364, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page, theme: theme));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets(
    'review',
    (t) => shoot(t, 'broker_update', brokerUpdateReview()),
  );
  testWidgets(
    'review, light',
    (t) => shoot(
      t,
      'broker_update_light',
      brokerUpdateReview(),
      theme: lightTheme(),
    ),
  );
  testWidgets(
    'restarting',
    (t) => shoot(t, 'broker_update_restart', brokerUpdateRestart()),
  );
  testWidgets(
    'confirmed',
    (t) => shoot(t, 'broker_update_done', brokerUpdateDone()),
  );
  testWidgets(
    'rolled back',
    (t) => shoot(t, 'broker_update_rolled_back', brokerUpdateRolledBack()),
  );
  testWidgets(
    'external',
    (t) => shoot(t, 'broker_update_external', brokerUpdateExternal()),
  );

  testWidgets('a field keeps what is typed across rebuilds', (t) async {
    final typed = <String>[];
    Widget sheet(String? value) => frame(
      TaskSheet(
        dialog: true,
        vm: TaskSheetVm(
          title: 'Update plant',
          blocks: [
            SheetField(id: 'confirm', label: 'Type plant', value: value),
          ],
        ),
        onText: (id, text) => typed.add('$id:$text'),
      ),
    );
    await t.pumpWidget(sheet(''));
    await t.enterText(find.byType(TextField), 'pla');
    await t.pumpWidget(sheet('pla'));
    expect(find.text('pla'), findsOneWidget);
    expect(typed, ['confirm:pla']);
    // Not a secret: the text is shown.
    expect(t.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
  });
}
