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
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:window_manager/window_manager.dart';

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
    // The window opens where the user left it and as large (once it is
    // ready to show); the steps below count on the boards' 1440 × 900.
    await settle(tester, 1000);
    await windowManager.setSize(const Size(1440, 900));
    await windowManager.center();
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
    if (find.text('mock').evaluate().isNotEmpty) {
      await tester.tap(find.text('mock').first);
      await settle(tester, 2500);
      await shot(tester, '01b_explorer_mock');
      store.dispatchSync(
        SelectNodeAction('wy/edge/downstream/modbus/line1/ahu1'),
      );
      await settle(tester, 3000);
      await shot(tester, '01d_explorer_device');
      final point = find.text('setpoint');
      if (point.evaluate().isNotEmpty) {
        await tester.tap(point.last);
        await settle(tester, 2000);
        await shot(tester, '01e_explorer_point');
      }
      store.dispatchSync(
        SelectNodeAction('wy/edge/downstream/modbus/line1/ahu1'),
      );
      await settle(tester);
      // The tab: the header's Actions ▾ (first) opens the node menu.
      await tester.tap(find.text('Actions').last);
      await settle(tester, 1000);
      await shot(tester, '01c_explorer_actions');
      final readId = find.text('Read Device Identification');
      if (readId.evaluate().isNotEmpty) {
        await tester.tap(readId.first);
        await settle(tester, 800);
        await tester.tap(find.text('Run now').last);
        await settle(tester, 2500);
        await shot(tester, '01f_explorer_action_result');
      }
      await tester.tap(find.text('Points').first);
      await settle(tester, 500);

      // One frame per node kind (docs/design/specs/explorer.md "Frames by
      // node kind"): none of them shows the device's points.
      for (final (shotName, key) in [
        ('01g_explorer_flow', 'wy/edge/dataflows/ahu2_ctl'),
        ('01h_explorer_link', 'wy/edge/downstream/modbus'),
        ('01i_explorer_connection', 'wy/edge/downstream/modbus/line1'),
        ('01j_explorer_storage', 'wy/edge/storage/line1'),
        ('01k_explorer_storage_folder', 'wy/edge/storage/line1/test'),
        ('01l_explorer_broker', 'wy/edge/upstream/central'),
      ]) {
        store.dispatchSync(SelectNodeAction(key));
        await settle(tester, 2500);
        // The frame's first tab: Contents, or a flow's Parameters.
        final first = find.text('Contents').evaluate().isNotEmpty
            ? 'Contents'
            : 'Parameters';
        await tester.tap(find.text(first).first);
        await settle(tester, 500);
        await shot(tester, shotName);
        debugPrint(
          '$shotName: points tab ${find.text('Points').evaluate().isNotEmpty}'
          ', overflow ${tester.takeException()}',
        );
        if (key.endsWith('/ahu2_ctl')) {
          // The header's Actions ▾ (before the Actions tab) builds the
          // node menu; the shot cannot hold the overlay, so it only must
          // not throw (its header is covered by ui/test/long_names_test).
          await tester.tap(find.text('Actions').first);
          await settle(tester, 1000);
          debugPrint('flow menu: overflow ${tester.takeException()}');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester, 500);
          final edit = find.text('Edit dataflow');
          if (edit.evaluate().isNotEmpty) {
            await tester.tap(edit.first);
            await settle(tester, 3500);
            await shot(tester, '01g3_explorer_flow_editor');
            debugPrint('editor route: ${appRouter.current.name}');
            await tester.tap(find.byType(IconButton).last);
            await settle(tester);
          }
        }
      }
    }

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
      if (name == 'Flows' && find.text('ahu2_ctl').evaluate().isNotEmpty) {
        await tester.tap(find.text('ahu2_ctl').first);
        await settle(tester, 1000);
        await shot(tester, '03b_flows_selected');
        await tester.tap(find.text('Edit dataflow').first);
        await settle(tester, 3500);
        await shot(tester, '03c_flow_editor');
        // Blocks of the owner's concat check: a variable (one field Value)
        // and concat (bound inputs show the values that come in).
        for (final (b, n) in [('concat1', '03d'), ('string1', '03e')]) {
          final f = find.descendant(
            of: find.byType(FlowCanvas),
            matching: find.text(b),
          );
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first, warnIfMissed: false);
            await settle(tester, 800);
            await shot(tester, '${n}_flow_$b');
          }
        }
        // The editor's own close, in its top bar: the inspector's eye
        // buttons come after it.
        await tester.tap(
          find
              .byWidgetPredicate((w) => w is AppIcon && w.name == 'ui_close')
              .first,
        );
        await settle(tester);
      }
      if (name == 'Assistant' && find.byType(TextField).evaluate().isNotEmpty) {
        await tester.enterText(
          find.byType(TextField).last,
          'What does modbus read on this site?',
        );
        await settle(tester, 300);
        await tester.tap(find.text('Ask').last);
        await settle(tester, 6000);
        await shot(tester, '07b_assistant_ask');
        final refused = find.textContaining('started no task');
        debugPrint('assistant refusal shown: ${refused.evaluate().isNotEmpty}');
        if (find.text('OK').evaluate().isNotEmpty) {
          await tester.tap(find.text('OK').last);
          await settle(tester, 500);
        }
        await tester.tap(find.text('What it may do').first);
        await settle(tester, 500);
        await shot(tester, '07c_assistant_rights');
      }
      if (name == 'Links' && find.text('modbus').evaluate().isNotEmpty) {
        await tester.tap(find.text('modbus').first);
        await settle(tester);
        await shot(tester, '0${i + 2}b_links_modbus');
      }
    }
  }, skip: gateway.isEmpty);
}
