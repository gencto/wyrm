// Add a link end to end against a demo gateway (the macOS app):
//
//   cd studio/app && flutter test integration_test/install_test.dart \
//     -d macos --dart-define=WYRM_GATEWAY=http://127.0.0.1:8444
//
// Installs the built-in driver `mock` as `studio-e2e`, then removes it
// through Links. Screens go to the app's temp folder (`screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/run_env.dart';
import 'package:business/environment.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    final boundary = tester
        .renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))
        .first;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/wyrm-screens')
      ..createSync(recursive: true);
    debugPrint('screen ${dir.path}/$name.png');
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('install mock as a link, then remove it', (tester) async {
    await runEnv(await Environment.dev());
    await settle(tester, 2500);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'wyrm-demo-1');
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);

    await tester.tap(find.text('Links').first);
    await settle(tester, 2500);
    await tester.tap(find.text('Add a link').first);
    await settle(tester, 3000);
    await shot(tester, '10_install_choose');

    await tester.tap(find.text('Mock').first);
    await settle(tester, 600);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    final name = find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == 'mock',
    );
    if (name.evaluate().isNotEmpty) {
      await tester.enterText(name.first, 'studio-e2e');
    } else {
      await tester.enterText(find.byType(EditableText).last, 'studio-e2e');
    }
    await settle(tester, 600);
    await shot(tester, '11_install_where');

    await tester.tap(find.text('Install').last);
    await settle(tester, 6000);
    await shot(tester, '12_install_result');
    expect(find.textContaining('is installed'), findsWidgets);

    await tester.tap(find.text('Back to Links'));
    await settle(tester, 3000);
    await tester.tap(find.text('studio-e2e').first);
    await settle(tester);
    await tester.ensureVisible(find.text('Remove link'));
    await settle(tester, 400);
    await tester.tap(find.text('Remove link'));
    await settle(tester, 800);
    await tester.tap(find.text('Remove').last);
    await settle(tester, 4000);
    await shot(tester, '13_removed');
    expect(find.text('studio-e2e'), findsNothing);
  }, skip: gateway.isEmpty);
}
