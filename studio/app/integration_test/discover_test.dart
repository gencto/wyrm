// Find on this network end to end (the macOS app, ADR 0050 §2): a wyrmd
// whose gateway listens off loopback with TLS announces `_wyrm._tcp`; the
// log-in page finds it, shows its CA code and pins it.
//
//   cd studio/app && flutter test integration_test/discover_test.dart \
//     -d macos --dart-define=WYRM_DISCOVER_SITE=lab
//
// The pin stays in the app's store (Remember does not drop pins).
// Screens go to the app's temp folder (`screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/run_env.dart';
import 'package:business/environment.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

// ignore: do_not_use_environment, a test parameter.
const site = String.fromEnvironment('WYRM_DISCOVER_SITE');

/// `address:port` to probe when the browse finds nothing (a range of one).
// ignore: do_not_use_environment, a test parameter.
const probe = String.fromEnvironment('WYRM_DISCOVER_PROBE');

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
    int seconds = 20,
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

  testWidgets('find the gateway of $site, check its code, trust it', (
    tester,
  ) async {
    await runEnv(await Environment.dev());
    await settle(tester, 2500);

    await tester.tap(find.text('Find on this network'));
    await settle(tester, 9500);
    await shot(tester, '19_discover_after_browse');
    if (find.text(site).evaluate().isEmpty && probe.isNotEmpty) {
      // Nothing found: probe the one address instead.
      final (address, port) = (probe.split(':')[0], probe.split(':')[1]);
      final range = find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            RegExp(r'^[\d.]+/\d+$').hasMatch(w.controller.text),
      );
      await tester.enterText(range.first, address);
      final ports = find.byWidgetPredicate(
        (w) =>
            w is EditableText && RegExp(r'^\d+$').hasMatch(w.controller.text),
      );
      await tester.enterText(ports.last, port);
      await settle(tester, 400);
      await tester.tap(find.text('Probe'));
      await settle(tester, 4000);
      await shot(tester, '19b_discover_probed');
    }
    await until(tester, find.text(site));
    await settle(tester, 9000);
    await shot(tester, '20_discover_found');

    await tester.tap(find.text(site).first);
    await settle(tester, 2000);
    await shot(tester, '21_discover_picked');
    final card = find.textContaining('check its certificate');
    if (card.evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('It matches'));
      await settle(tester, 3000);
      await shot(tester, '22_discover_trusted');
    }
    expect(find.textContaining('pinned on this computer'), findsWidgets);
    // The probe of the log-in page goes through the pin too: the status
    // line keeps `picked from this network`, not `No answer from`.
    await settle(tester, 2000);
    expect(find.textContaining('picked from this network'), findsOneWidget);
    expect(find.textContaining('No answer from'), findsNothing);
  }, skip: site.isEmpty);
}
