// The views lab (docs/design/specs/genui-views.md §7) in the real macOS app
// against the demo's plant broker:
//
//   (examples/demo/run.sh running)
//   cd studio/app && flutter test integration_test/views_lab_test.dart \
//     -d macos --dart-define=WYRM_GATEWAY=http://127.0.0.1:8446
//
// It walks the brief's "done when" list and writes a PNG of each step to
// the app's temp folder (printed as `screen <path>`). The setpoint and the
// marker word it writes are put back at the end.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/common/app_store.dart';
import 'package:app/run_env.dart';
import 'package:business/environment.dart';
import 'package:business/redux/views/actions/run_view_action.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/inputs/switch_row.dart';
import 'package:ui/views/view_lamp.dart';
import 'package:ui/views/view_placeholder.dart';
import 'package:ui/views/view_project_shell.dart';
import 'package:ui/views/view_slider.dart';
import 'package:ui/views/view_surface.dart';
import 'package:ui/views/view_trend.dart';
import 'package:window_manager/window_manager.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');

const _sp = 'wy/plant/downstream/bacnet/sim/d1/sp';
const _mw = 'wy/plant/downstream/s7/plc1/cpu/mw';
const _temp = 'wy/plant/downstream/s7/plc1/cpu/temp';

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

  testWidgets('the views lab on the demo plant', (tester) async {
    await runEnv(await Environment.dev());
    await settle(tester, 1000);
    await windowManager.setSize(const Size(1760, 1000));
    await windowManager.center();
    await settle(tester, 2500);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'wyrm-demo-1');
    await tester.tap(find.text('Log in').last);
    await settle(tester, 5000);
    final store = AppStore.of(
      tester.element(find.byType(Router<Object>).first),
    );
    Object? value(String key) => store.state.views.data['/$key'];

    // Reached from System ▸ Maintenance ▸ Elsewhere.
    await tester.tap(find.text('System').first);
    await settle(tester, 2000);
    await tester.tap(find.text('Maintenance').first);
    await settle(tester);
    await tester.ensureVisible(find.text('Views lab'));
    await settle(tester, 400);
    await tester.tap(find.text('Views lab'));
    await settle(tester, 4000);

    // 1. demo-plant with live values.
    expect(find.byType(ViewSurface), findsOneWidget);
    expect(find.byType(ViewPlaceholder), findsNothing);
    final t0 = value(_temp);
    final counter0 = value('wy/plant/downstream/s7/plc1/cpu/counter');
    debugPrint('live: temp $t0, counter $counter0, sp ${value(_sp)}');
    expect(t0, isA<num>());
    expect(value(_sp), isA<num>());
    await shot(tester, 'views_01_demo_plant');
    await settle(tester, 6000);
    final counter1 = value('wy/plant/downstream/s7/plc1/cpu/counter');
    debugPrint('live: counter $counter0 → $counter1 after 6 s');
    expect(counter1, isNot(counter0));

    // 2. The template: one card per BACnet device (a node, not a point).
    final devices = store.state.views.data.keys
        .where((k) => k.endsWith(r'/$name') && k.contains('~children'))
        .toList();
    debugPrint('template: $devices');
    expect(find.byType(ViewSlider), findsNWidgets(devices.length));
    expect(devices, isNotEmpty);

    // 3. The slider writes the setpoint after a confirm; the value comes
    // back from the device.
    final before = value(_sp)! as num;
    await tester.drag(find.byType(Slider).first, const Offset(40, 0));
    await settle(tester, 800);
    await shot(tester, 'views_02_confirm');
    expect(find.text('Write this value?'), findsOneWidget);
    expect((value(_sp)! as num).toDouble(), before.toDouble());
    await tester.tap(find.text('Write'));
    await settle(tester, 4000);
    final after = value(_sp)! as num;
    debugPrint('set: sp $before → $after (${store.state.views.result})');
    expect(after, isNot(before));
    await shot(tester, 'views_03_written');

    // The button with the document's own question.
    await tester.tap(find.text('Reset S7 marker word').first);
    await settle(tester, 800);
    expect(find.text('Write 0 to MW10 on plc1?'), findsOneWidget);
    await tester.tap(find.text('Write'));
    await settle(tester, 3000);
    debugPrint('set: mw (${store.state.views.result})');
    expect(store.state.views.result, 'Wrote 0 to $_mw');

    // 4. Widths and themes.
    await tester.tap(find.text('Panel 10"'));
    await settle(tester, 1200);
    await shot(tester, 'views_04_panel');
    await tester.tap(find.text('Phone').first);
    await settle(tester, 1200);
    await shot(tester, 'views_05_phone');
    await tester.tap(find.bySemanticsLabel('Light theme').first);
    await settle(tester, 1200);
    await shot(tester, 'views_06_phone_light');
    await tester.tap(find.text('Desktop').first);
    await settle(tester, 1200);
    await shot(tester, 'views_07_desktop_light');

    // 5. Project: the menu in its three forms, wyrm.open, breadcrumbs, back.
    await tester.tap(find.byType(AppSwitch));
    await settle(tester, 2500);
    expect(find.byType(ViewProjectShell), findsOneWidget);
    expect(find.text('BACNET DEVICES'), findsOneWidget);
    await shot(tester, 'views_08_project_desktop_light');
    await tester.tap(find.bySemanticsLabel('Dark theme').first);
    await settle(tester, 1200);
    await tester.tap(find.text('d1').last);
    await settle(tester, 3000);
    debugPrint(
      'open: stack ${store.state.views.stack.map((p) => p.page).toList()}',
    );
    expect(store.state.views.stack.map((p) => p.page), ['overview', 'device']);
    expect(find.text('BACnet devices › Device d1'), findsOneWidget);
    expect(find.text('Change setpoint'), findsOneWidget);
    expect(find.byType(ViewTrend), findsOneWidget);
    await shot(tester, 'views_09_device_desktop');
    await tester.tap(find.text('Panel 10"'));
    await settle(tester);
    await shot(tester, 'views_10_device_panel');
    await tester.tap(find.text('Phone').first);
    await settle(tester);
    await shot(tester, 'views_11_device_phone');
    // A kiosk is a wall screen: its density on the wide frame.
    await tester.tap(find.text('Desktop').first);
    await settle(tester, 800);
    await tester.tap(find.text('Kiosk'));
    await settle(tester);
    await shot(tester, 'views_12_device_kiosk');
    await tester.tap(find.text('By width'));
    await settle(tester);
    await tester.tap(find.text('Back').last);
    await settle(tester, 2500);
    expect(store.state.views.stack.map((p) => p.page), ['overview']);
    expect(find.text('Reset S7 marker word'), findsOneWidget);
    await tester.tap(find.byType(AppSwitch));
    await settle(tester);

    // 6. pump-station (invented keys): placeholders and checks, then the
    // refine turn on the same surface.
    await tester.tap(find.text('pump-station'));
    await settle(tester, 3000);
    await shot(tester, 'views_13_pump_station');
    final trend = tester.state(find.byType(ViewTrend));
    expect(find.byType(ViewLamp), findsNothing);
    final checks = [
      for (final c in store.state.views.checks) '${c.level}: ${c.text}',
    ];
    debugPrint('checks: ${checks.join(' | ')}');
    await tester.tap(find.text('Apply the refine turn'));
    await settle(tester, 2500);
    expect(find.byType(ViewLamp), findsNWidgets(2));
    expect(tester.state(find.byType(ViewTrend)), same(trend));
    await shot(tester, 'views_14_refined');
    await tester.tap(find.text('A2UI'));
    await settle(tester, 800);
    await shot(tester, 'views_15_messages');
    await tester.tap(find.text('demo-plant'));
    await settle(tester, 2500);
    await tester.tap(find.text('Data'));
    await settle(tester, 800);
    await shot(tester, 'views_16_data');

    // Put back what was written.
    await store.dispatchAndWait(
      RunViewAction('wyrm.set', {'key': _sp, 'value': before}),
    );
    await store.dispatchAndWait(
      RunViewAction('wyrm.set', {'key': _mw, 'value': 1234}),
    );
    await settle(tester, 2000);
    debugPrint('restored: sp ${value(_sp)}');
  }, skip: gateway.isEmpty);
}
