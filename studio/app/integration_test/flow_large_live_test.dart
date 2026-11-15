// A large flow on the demo, in the real app (flow-editor.md §25):
//
//   (examples/demo/run.sh running, a flow with ~60 blocks on central)
//   cd studio/app && flutter test integration_test/flow_large_live_test.dart \
//     -d macos --dart-define=WYRM_GATEWAY=http://127.0.0.1:8445 \
//     --dart-define=WYRM_FLOW=dvpsm-bot
//
// It opens the flow, writes a PNG of the editor as it opens, after a pan
// by two fingers and after Tidy up (printed as `screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/common/app_store.dart';
import 'package:app/navigation/app_router.dart';
import 'package:app/navigation/go_action.dart';
import 'package:app/run_env.dart';
import 'package:business/environment.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');
// ignore: do_not_use_environment, a test parameter.
const flow = String.fromEnvironment('WYRM_FLOW', defaultValue: 'dvpsm-bot');
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

  testWidgets('a large flow opens readable and pans', (tester) async {
    await runEnv(await Environment.dev());
    await settle(tester, 1000);
    // The window keeps the size it was left at (1440 × 900 by the
    // screens test); asking the window manager waits for a foreground
    // window that a run from the terminal may never get.
    await settle(tester, 2500);
    final fields = find.byType(EditableText);
    final store = AppStore.of(
      tester.element(find.byType(Router<Object>).first),
    );
    debugPrint('live: login page');
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), password);
    for (var i = 0; i < 4 && store.state.session.token == null; i++) {
      await tester.tap(find.text('Log in').last, warnIfMissed: false);
      await settle(tester, 3000);
    }
    debugPrint('live: logged in ${store.state.session.token != null}');
    await store.dispatchAndWait(GoAction.push(FlowEditorRoute(id: flow)));
    await settle(tester, 5000);
    await shot(tester, 'flow_large_open');

    final canvas = tester.getRect(find.byType(FlowCanvas));
    int shown() =>
        tester.widgetList<FlowBlockView>(find.byType(FlowBlockView)).where((b) {
          final r = tester.getRect(find.byWidget(b));
          return canvas.overlaps(r);
        }).length;
    debugPrint(
      'flow large: ${tester.widgetList(find.byType(FlowBlockView)).length} '
      'blocks, ${shown()} in view',
    );

    // Two fingers on the trackpad, up and to the left.
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(canvas.center);
    for (var i = 0; i < 20; i++) {
      await pad.panZoomUpdate(canvas.center, pan: Offset(-20.0 * i, -30.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pad.panZoomEnd();
    await settle(tester, 500);
    await shot(tester, 'flow_large_panned');
  });
}
