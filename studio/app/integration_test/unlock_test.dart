// The device unlock end to end in the macOS app (ADR 0050 §1): a password
// login on a gateway_dev, the offer with this Mac's words, `Not now`, and
// the Secure Enclave key that `device_key` makes in this build.
//
//   cargo run -p wyrm-gateway --example gateway_dev   # prints PORT=<n>
//   cd studio/app && flutter test integration_test/unlock_test.dart \
//     -d macos --dart-define=WYRM_UNLOCK_GATEWAY=http://127.0.0.1:<n>
//
// Signing needs a finger on the sensor, so this test does not sign; the
// business live test signs with a software key against the same gateway.
// Screens go to the app's temp folder (`screen <path>`).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/run_env.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/environment.dart';
import 'package:device_key/device_key.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_UNLOCK_GATEWAY');

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

  testWidgets('this Mac makes a Secure Enclave key', (tester) async {
    final keys = DeviceKey();
    final available = await keys.isAvailable();
    debugPrint('device key: $available');
    expect(available.available, isTrue, reason: 'Touch ID is enrolled here');
    final pub = await keys.create('wyrm-integration-test');
    expect(pub.alg, 'es256');
    expect(pub.publicKey, hasLength(65));
    expect(pub.publicKey.first, 4, reason: 'an uncompressed P-256 point');
    await keys.delete('wyrm-integration-test');
    // A deleted key cannot sign, and says so without a prompt.
    final r = await keys.sign(
      'wyrm-integration-test',
      Uint8List.fromList([1, 2, 3]),
      'test',
    );
    expect(r, isA<SignInvalidated>());
  });

  testWidgets('a password login offers Touch ID; Not now opens Studio', (
    tester,
  ) async {
    await runEnv(await Environment.dev());
    await settle(tester, 2500);
    // A start with a key shows `Welcome back`: go to the fields.
    if (find.text('Another account or gateway').evaluate().isNotEmpty) {
      await tester.tap(find.text('Another account or gateway'));
      await settle(tester);
    }
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'admin password');
    await settle(tester, 500);
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);
    await shot(tester, '30_unlock_offer');
    final s = StoreProvider.state<AppState>(
      tester.element(find.byType(Scaffold).first),
    )!;
    debugPrint(
      'device: available ${s.device.available} stage ${s.device.stage} '
      'offered ${s.device.offered} dontAsk ${s.device.dontAsk} '
      'policy ${s.device.policy} remember ${s.login.remember} '
      'gateway ${s.login.gateway}',
    );
    expect(find.text('Unlock with Touch ID next time?'), findsOneWidget);
    expect(find.text('Use Touch ID'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await settle(tester, 6000);
    await shot(tester, '31_unlock_not_now_studio');
    expect(find.text('Unlock with Touch ID next time?'), findsNothing);
  });
}
