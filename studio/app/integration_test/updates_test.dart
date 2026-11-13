// Update a package and roll it back, end to end against a demo gateway
// (the macOS app, ADR 0048 §1):
//
//   cd studio/app && flutter test integration_test/updates_test.dart \
//     -d macos --dart-define=WYRM_GATEWAY=http://127.0.0.1:8446 \
//     --dart-define=WYRM_LINK=reg1
//
// Needs a link (`WYRM_LINK`) of a package whose repository has a newer
// version: Links ▸ Updates ▸ the row ▸ the review ▸ Update, the health
// check, the result; then Roll back from the result's restore point.
// Screens go to the app's temp folder (`screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

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
const link = String.fromEnvironment('WYRM_LINK', defaultValue: 'reg1');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(TaskSheet), matching: f);

  testWidgets('update a package, then roll it back', (tester) async {
    await runEnv(await Environment.dev());
    await settle(tester, 2500);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'wyrm-demo-1');
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);

    await tester.tap(find.text('Links').first);
    await until(tester, find.text('Updates'));
    await settle(tester, 1000);
    await shot(tester, '50_links_updates_badge');
    await tester.tap(find.text('Updates'));
    await settle(tester);
    await tester.tap(find.text(link).first);
    await until(tester, inSheet(find.textContaining('Update links')));
    await shot(tester, '51_update_review');

    await tester.tap(inSheet(find.textContaining('Update links')));
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, '52_update_progress');
    // The health check ends by itself (3 s stable, 12 s after a hot start).
    await until(tester, inSheet(find.text('done')), seconds: 150);
    await shot(tester, '53_update_done');
    expect(inSheet(find.textContaining('Roll back to')), findsWidgets);

    await tester.tap(inSheet(find.textContaining('Roll back to')).first);
    await settle(tester, 800);
    await shot(tester, '54_rollback_confirm');
    await tester.tap(find.text('Roll back').last);
    await until(tester, inSheet(find.text('rolled back')), seconds: 150);
    await shot(tester, '55_rolled_back');
    await tester.tap(inSheet(find.text('Close')));
    await settle(tester, 1000);
  });
}
