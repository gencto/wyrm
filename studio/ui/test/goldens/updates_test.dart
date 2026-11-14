import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/theme/common.dart';

import '../frames/harness.dart';
import '../frames/updates.dart';

/// Boards `LinkUpdate`, `LinkUpdateProgress`, `LinkUpdateDone` and
/// `LinkUpdateRolledBack` (ADR 0048 §1), one golden each: the Links
/// workspace without the shell with the update drawer. The review also in
/// the light theme.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

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
    (t) => shoot(t, 'link_update', linkUpdateReview()),
  );
  testWidgets(
    'review, light',
    (t) => shoot(
      t,
      'link_update_light',
      linkUpdateReview(),
      theme: lightTheme(),
    ),
  );
  testWidgets(
    'progress',
    (t) => shoot(t, 'link_update_progress', linkUpdateProgress()),
  );
  testWidgets(
    'done',
    (t) => shoot(t, 'link_update_done', linkUpdateDone()),
  );
  testWidgets(
    'rolled back',
    (t) => shoot(t, 'link_update_rolled_back', linkUpdateRolledBack()),
  );

  testWidgets('the sheet reports its controls', (t) async {
    final got = <String>[];
    await t.pumpWidget(
      frame(
        Row(
          children: [
            const Spacer(),
            TaskSheet(
              vm: const TaskSheetVm(
                title: 'Update',
                blocks: [
                  SheetOption(id: 'auto', label: 'Roll back', value: true),
                  SheetOption(
                    id: 'point',
                    label: 'Restore point',
                    value: true,
                    enabled: false,
                    reason: 'the store format changes',
                  ),
                  SheetRow(
                    text: '0.4.2',
                    action: 'rollback',
                    actionLabel: 'Roll back to 0.4.2…',
                  ),
                ],
                secondary: 'Cancel',
                primary: 'Update 2 links',
              ),
              onPrimary: () => got.add('primary'),
              onSecondary: () => got.add('secondary'),
              onToggle: (id, {required value}) => got.add('$id=$value'),
              onAction: got.add,
              onClose: () => got.add('close'),
            ),
          ],
        ),
      ),
    );
    await t.tap(find.text('Roll back'));
    // A locked option does not answer.
    await t.tap(find.text('Restore point'));
    await t.tap(find.text('Roll back to 0.4.2…'));
    await t.tap(find.text('Cancel'));
    await t.tap(find.text('Update 2 links'));
    expect(got, ['auto=false', 'rollback', 'secondary', 'primary']);
  });

  testWidgets('a disabled primary does nothing and says why', (t) async {
    var taps = 0;
    await t.pumpWidget(
      frame(
        TaskSheet(
          dialog: true,
          vm: const TaskSheetVm(
            title: 'A task',
            blocks: [],
            primary: 'Update',
            primaryEnabled: false,
            primaryReason: 'needs config on sys/links',
          ),
          onPrimary: () => taps++,
        ),
      ),
    );
    await t.tap(find.text('Update'), warnIfMissed: false);
    expect(taps, 0);
    expect(find.byTooltip('needs config on sys/links'), findsOneWidget);
  });
}
