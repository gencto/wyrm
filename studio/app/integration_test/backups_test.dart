// Backups end to end against a demo gateway (the macOS app, ADR 0048 §3):
//
//   cd studio/app && flutter test integration_test/backups_test.dart \
//     -d macos --dart-define=WYRM_GATEWAY=http://127.0.0.1:8446
//
// 1. System › Maintenance ▸ Back up…: two sections (control plane, broker
//    storage), the job's progress, its result, Download in parts into the
//    app's temp folder, the SHA-256 compared.
// 2. Links ▸ a link ▸ Back up…: a link backup, downloaded the same way.
// 3. Links ▸ Add a link ▸ From a backup: that file, under a new id; then
//    the new link is removed.
//
// The two system dialogs (choose a folder, choose a file) are answered by
// the test. Screens go to the app's temp folder (`screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/common/files.dart';
import 'package:app/run_env.dart';
import 'package:business/environment.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/task_sheet.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');

// ignore: do_not_use_environment, a test parameter.
const link = String.fromEnvironment('WYRM_LINK', defaultValue: 'mock');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps until [what] is there, at most [seconds].
  Future<void> until(
    WidgetTester tester,
    Finder what, {
    int seconds = 60,
  }) async {
    for (var i = 0; i < seconds * 5; i++) {
      if (what.evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    fail('not shown in $seconds s: $what');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    // The whole window, dialogs included.
    final view = tester.binding.renderViews.first;
    final ratio = view.flutterView.devicePixelRatio;
    final image = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & (view.size * ratio),
      pixelRatio: 1 / ratio,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/wyrm-screens')
      ..createSync(recursive: true);
    debugPrint('screen ${dir.path}/$name.png');
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(f.first);
  }

  testWidgets('back up the broker and a link, restore the link', (
    tester,
  ) async {
    final out = Directory('${Directory.systemTemp.path}/wyrm-backups')
      ..createSync(recursive: true);
    for (final f in out.listSync()) {
      f.deleteSync(recursive: true);
    }
    directoryPicker = (_) async => out.path;
    filePathPicker = (ext) async => out
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => ext.any((e) => p.endsWith('.$e')))
        .firstOrNull;

    await runEnv(await Environment.dev());
    await settle(tester, 2500);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'wyrm-demo-1');
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);

    // 1. The broker.
    await tester.tap(find.text('System').first);
    await settle(tester, 2500);
    await tester.tap(find.text('Maintenance').first);
    await settle(tester, 2500);
    await shot(tester, '30_maintenance');
    await tap(tester, find.text('Back up…'));
    await until(tester, find.text('What goes in'.toUpperCase()));
    await settle(tester);
    await shot(tester, '31_backup_choose');
    for (final name in [
      'Dataflows',
      'History',
      'Links',
      'Installed packages',
      'wyrmd.json5 (read only)',
    ]) {
      // The section of the dialog, not the workspace of that name.
      await tap(
        tester,
        find.descendant(of: find.byType(TaskSheet), matching: find.text(name)),
      );
      await settle(tester, 300);
    }
    await shot(tester, '32_backup_two_sections');
    await tap(tester, find.text('Back up'));
    await until(tester, find.text('Backup ready'));
    await shot(tester, '33_backup_done');
    await tap(tester, find.text('Download…'));
    await until(tester, find.textContaining('SHA-256 checked'));
    await shot(tester, '34_backup_downloaded');
    final broker = out.listSync().whereType<File>().firstWhere(
      (f) => f.path.endsWith('.wyrm-backup'),
    );
    debugPrint('downloaded ${broker.path} ${broker.lengthSync()} bytes');
    expect(broker.lengthSync(), greaterThan(0));
    await tap(tester, find.text('Show in Backups'));
    await settle(tester);
    await shot(tester, '35_backups_list');

    // 2. A link.
    await tester.tap(find.text('Links').first);
    await settle(tester, 2500);
    await tester.tap(find.text(link).first);
    await settle(tester);
    await shot(tester, '36_link_inspector');
    await tap(tester, find.text('Back up…'));
    await until(tester, find.text('What goes in'.toUpperCase()));
    await settle(tester);
    await shot(tester, '36_link_backup');
    await tap(tester, find.text('Back up $link'));
    await until(tester, find.text('Backup ready'));
    await tap(tester, find.text('Download…'));
    await until(tester, find.textContaining('SHA-256 checked'));
    await shot(tester, '37_link_backup_downloaded');
    final file = out.listSync().whereType<File>().firstWhere(
      (f) => f.path.endsWith('.wyrm-link'),
    );
    debugPrint('downloaded ${file.path} ${file.lengthSync()} bytes');
    await tap(tester, find.text('Show in Backups'));
    await settle(tester, 1000);

    // 3. Add a link ▸ From a backup, under a new id.
    await tester.tap(find.text('Add a link').first);
    await settle(tester, 3000);
    await tap(tester, find.text('From a backup'));
    await settle(tester, 600);
    await tap(tester, find.text('Choose a .wyrm-link file'));
    await settle(tester);
    await shot(tester, '38_from_backup_choose');
    await tap(tester, find.text('Continue'));
    await settle(tester);
    await shot(tester, '39_from_backup_check');
    await tap(tester, find.text('Continue'));
    await settle(tester);
    final name = find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == link,
    );
    await tester.enterText(name.first, 'studio-restored');
    await settle(tester, 600);
    await shot(tester, '40_from_backup_where');
    // The button, not the step of that name in the rail.
    await tester.tap(find.text('Install').last);
    await settle(tester, 8000);
    await shot(tester, '41_from_backup_result');
    expect(find.textContaining('is installed'), findsWidgets);

    await tester.tap(find.text('Back to Links'));
    await settle(tester, 3000);
    await tester.tap(find.text('studio-restored').first);
    await settle(tester);
    await tap(tester, find.text('Remove link'));
    await settle(tester, 800);
    await tester.tap(find.text('Remove').last);
    await settle(tester, 4000);
    expect(find.text('studio-restored'), findsNothing);
  });
}
