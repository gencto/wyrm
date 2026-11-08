// The real app against a demo gateway, on the desktop, with real fonts:
//
//   (examples/demo/run.sh running)
//   cd studio/app && flutter test integration_test -d macos \
//     --dart-define=WYRM_GATEWAY=http://127.0.0.1:8445
//
// It logs in and writes a PNG of each workspace to the app's temp folder
// (printed as `screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/navigation/app_router.dart';
import 'package:app/run_env.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/environment.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');
// ignore: do_not_use_environment, a test parameter.
const password = String.fromEnvironment(
  'WYRM_PASSWORD',
  defaultValue: 'wyrm-demo-1',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    final boundary = tester
        .renderObjectList<RenderRepaintBoundary>(
          find.byType(RepaintBoundary),
        )
        .first;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    // The macOS app is sandboxed: its temp folder is inside its container.
    final dir = Directory('${Directory.systemTemp.path}/wyrm-screens')
      ..createSync(recursive: true);
    debugPrint('screen ${dir.path}/$name.png');
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('log in and visit every workspace', (tester) async {
    await runEnv(await Environment.dev());
    await settle(tester, 2500);
    await shot(tester, '00_login');

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), password);
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);
    final store = StoreProvider.backdoorInheritedWidget<AppState>(
      tester.element(find.byType(Router<Object>).first),
    );
    debugPrint(
      'after log in: token=${store.state.session.token} '
      'site=${store.state.site.name} wait=${store.state.wait} '
      'login=${store.state.login} '
      'route=${appRouter.current.name}',
    );
    await shot(tester, '01_explorer');

    for (final (i, name) in [
      'Links',
      'Flows',
      'History',
      'Access',
      'Sites',
      'Assistant',
      'System',
    ].indexed) {
      await tester.tap(find.text(name).first);
      await settle(tester, 2500);
      await shot(tester, '0${i + 2}_${name.toLowerCase()}');
      if (name == 'Links' && find.text('modbus').evaluate().isNotEmpty) {
        await tester.tap(find.text('modbus').first);
        await settle(tester);
        await shot(tester, '0${i + 2}b_links_modbus');
      }
    }
  }, skip: gateway.isEmpty);
}
