import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/theme/common.dart';

import '../frames/backups.dart';
import '../frames/harness.dart';

/// Boards `Backup`, `BackupProgress`, `BackupDone`, `BackupRestore` and
/// `LinkBackup` (ADR 0048 §3), one golden each: the dialog over the
/// workspace it was opened from. `Backup` also in the light theme.
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

  testWidgets('choose', (t) => shoot(t, 'backup', backupChoose()));
  testWidgets(
    'choose, light',
    (t) => shoot(t, 'backup_light', backupChoose(), theme: lightTheme()),
  );
  testWidgets(
    'progress',
    (t) => shoot(t, 'backup_progress', backupProgress()),
  );
  testWidgets('done', (t) => shoot(t, 'backup_done', backupDone()));
  testWidgets('restore', (t) => shoot(t, 'backup_restore', backupRestore()));
  testWidgets('link', (t) => shoot(t, 'link_backup', linkBackup()));

  testWidgets('the passphrase stays typed when the check adds blocks', (
    t,
  ) async {
    // Not reviewed, checked: the restore dialog before and after the check.
    Widget sheet(List<SheetBlock> before) => frame(
      TaskSheet(
        dialog: true,
        vm: TaskSheetVm(
          title: 'Restore',
          blocks: [
            ...before,
            const SheetField(
              id: 'passphrase',
              label: 'Passphrase',
              secret: true,
            ),
          ],
        ),
      ),
    );
    await t.pumpWidget(
      sheet(const [SheetCard(title: 'The file is on the broker')]),
    );
    await t.enterText(find.byType(TextField), 'correct-horse-battery');
    await t.pumpWidget(
      sheet(const [
        SheetLabel('Checked'),
        SheetCard(title: 'From plant'),
        SheetCard(title: 'The same keys'),
        SheetSection(id: 'control', name: 'Control plane', on: true),
        SheetOption(id: 'accept', label: 'Accept', value: false),
      ]),
    );
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'correct-horse-battery',
    );
  });

  testWidgets('sections, chips, choices and fields report', (t) async {
    final got = <String>[];
    await t.pumpWidget(
      frame(
        TaskSheet(
          dialog: true,
          vm: const TaskSheetVm(
            title: 'Back up',
            blocks: [
              SheetSection(
                id: 'control',
                name: 'Control plane',
                on: true,
                locked: true,
              ),
              SheetSection(
                id: 'history',
                name: 'History',
                on: true,
                chips: [
                  SheetChip(id: '7', label: 'Last 7 days'),
                  SheetChip(id: '30', label: 'Last 30 days', on: true),
                ],
              ),
              SheetSection(
                id: 'links',
                name: 'Links',
                on: true,
                multi: true,
                chips: [SheetChip(id: 'modbus', label: 'modbus', on: true)],
              ),
              SheetSection(
                id: 'packages',
                name: 'Installed packages',
                on: false,
                chips: [SheetChip(id: 'x', label: 'hidden chip')],
              ),
              SheetField(id: 'passphrase', label: 'Passphrase', secret: true),
              SheetChoice(
                id: 'where',
                options: [
                  ('computer', 'This computer'),
                  ('store', 'File store link…'),
                ],
                selected: 'computer',
                reasons: {'store': 'the host lists no link'},
              ),
            ],
          ),
          onToggle: (id, {required value}) => got.add('$id=$value'),
          onPick: (g, v) => got.add('$g:$v'),
          onText: (id, text) => got.add('$id:${text.length}'),
        ),
      ),
    );
    // A locked section does not answer.
    await t.tap(find.text('Control plane'));
    await t.tap(find.text('History'));
    await t.tap(find.text('Last 7 days'));
    await t.tap(find.text('modbus'));
    await t.tap(find.text('Installed packages'));
    // An option with a reason cannot be chosen.
    await t.tap(find.text('File store link…'));
    await t.tap(find.text('This computer'));
    await t.enterText(find.byType(TextField), 'correct-horse');
    expect(got, [
      'history=false',
      'history:7',
      'links:modbus',
      'packages=true',
      'where:computer',
      'passphrase:13',
    ]);
    // The chips of an unticked section are not shown.
    expect(find.text('hidden chip'), findsNothing);
    // A secret is obscured.
    expect(t.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    expect(find.byTooltip('the host lists no link'), findsOneWidget);
  });
}
