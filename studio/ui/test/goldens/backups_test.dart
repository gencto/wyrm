import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/backup_data.dart';
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
              slot: BackupSheetField.passphrase,
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
        SheetSection(name: 'Control plane', on: true),
        SheetOption(label: 'Accept', value: false),
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
          vm: TaskSheetVm(
            title: 'Back up',
            blocks: [
              SheetSection(
                name: 'Control plane',
                on: true,
                locked: true,
                onChanged: (on) => got.add('control=$on'),
              ),
              SheetSection(
                name: 'History',
                on: true,
                chips: [
                  SheetChip(
                    label: 'Last 7 days',
                    onTap: () => got.add('history:7'),
                  ),
                  SheetChip(
                    label: 'Last 30 days',
                    on: true,
                    onTap: () => got.add('history:30'),
                  ),
                ],
                onChanged: (on) => got.add('history=$on'),
              ),
              SheetSection(
                name: 'Links',
                on: true,
                multi: true,
                chips: [
                  SheetChip(
                    label: 'modbus',
                    on: true,
                    onTap: () => got.add('links:modbus'),
                  ),
                ],
                onChanged: (on) => got.add('links=$on'),
              ),
              SheetSection(
                name: 'Installed packages',
                on: false,
                chips: [
                  SheetChip(
                    label: 'hidden chip',
                    onTap: () => got.add('packages:x'),
                  ),
                ],
                onChanged: (on) => got.add('packages=$on'),
              ),
              // A section nobody listens to does not answer.
              const SheetSection(name: 'Storage', on: true),
              SheetField(
                slot: BackupSheetField.passphrase,
                label: 'Passphrase',
                secret: true,
                onChanged: (text) => got.add('passphrase:${text.length}'),
              ),
              SheetChoice(
                options: [
                  SheetChoiceOption(
                    label: 'This computer',
                    selected: true,
                    onPick: () => got.add('where:computer'),
                  ),
                  SheetChoiceOption(
                    label: 'File store link…',
                    reason: 'the host lists no link',
                    onPick: () => got.add('where:store'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // A locked section does not answer.
    await t.tap(find.text('Control plane'));
    await t.tap(find.text('History'));
    await t.tap(find.text('Last 7 days'));
    await t.tap(find.text('modbus'));
    await t.tap(find.text('Installed packages'));
    await t.tap(find.text('Storage'));
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

  testWidgets('a field is known by its slot, not by its label', (t) async {
    // The language changes the label; what was typed stays.
    Widget sheet(String label) => frame(
      TaskSheet(
        dialog: true,
        vm: TaskSheetVm(
          title: 'Restore',
          blocks: [
            SheetField(
              slot: BackupSheetField.passphrase,
              label: label,
              secret: true,
            ),
          ],
        ),
      ),
    );
    await t.pumpWidget(sheet('Passphrase'));
    await t.enterText(find.byType(TextField), 'correct-horse-battery');
    await t.pumpWidget(sheet('Пароль'));
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'correct-horse-battery',
    );
  });

  testWidgets('a field of another slot is another field', (t) async {
    Widget sheet(BackupSheetField slot) => frame(
      TaskSheet(
        dialog: true,
        vm: TaskSheetVm(
          title: 'Back up',
          blocks: [SheetField(slot: slot, label: 'Text')],
        ),
      ),
    );
    await t.pumpWidget(sheet(BackupSheetField.passphrase));
    await t.enterText(find.byType(TextField), 'secret');
    await t.pumpWidget(sheet(BackupSheetField.sendPath));
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });
}
