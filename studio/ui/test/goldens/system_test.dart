import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/system_page.dart';

import '../frames/harness.dart';
import '../frames/system.dart';

/// Boards `System`, `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`,
/// `SystemLog` and `SystemMaint`, one golden each (the workspace without
/// the shell: 1440 × 1000 less the rail and the top bar), and the states the
/// boards do not draw: loading, and no `config` on `sys`.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(1364, 944);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets(
    'overview',
    (t) => shoot(t, 'system_overview', systemOverview()),
  );
  testWidgets(
    'standby follows',
    (t) => shoot(t, 'system_avail', systemAvail()),
  );
  testWidgets(
    'standby behind',
    (t) => shoot(t, 'system_avail_lag', systemAvailLag()),
  );
  testWidgets(
    'no standby',
    (t) => shoot(t, 'system_avail_none', systemAvailNone()),
  );
  testWidgets('log', (t) => shoot(t, 'system_log', systemLog()));
  testWidgets('maintenance', (t) => shoot(t, 'system_maint', systemMaint()));
  testWidgets('loading', (t) => shoot(t, 'system_loading', systemLoading()));
  testWidgets(
    'no config on sys',
    (t) => shoot(t, 'system_no_rights', systemNoRights()),
  );
  testWidgets(
    'no config on sys, the log',
    (t) => shoot(t, 'system_log_no_rights', systemLogNoRights()),
  );

  testWidgets('below 1100 px the attention panel is under the main column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(systemOverview()));
    await tester.pump();
    final tiles = tester.getTopLeft(find.text('LINKS AND SITES'));
    final panel = tester.getTopLeft(find.text('NEEDS A LOOK · 3'));
    expect(panel.dy, greaterThan(tiles.dy));
    expect(panel.dx, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile with a destination is a link; others are not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1364, 944);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <String>[];
    final page = systemOverview();
    await tester.pumpWidget(
      frame(
        SystemPage(
          title: page.title,
          meta: page.meta,
          tabs: page.tabs,
          tab: page.tab,
          onTab: page.onTab,
          overview: page.overview,
          availability: page.availability,
          log: page.log,
          maintenance: page.maintenance,
          attention: page.attention,
          onAttention: tapped.add,
          onTile: tapped.add,
          onMeasure: page.onMeasure,
          onSource: page.onSource,
          onLevel: page.onLevel,
          onFilter: page.onFilter,
          onLines: page.onLines,
          onAround: page.onAround,
          onAuto: page.onAuto,
          onGetLog: page.onGetLog,
          onCopyLog: page.onCopyLog,
          onSaveLog: page.onSaveLog,
          onLogLevel: page.onLogLevel,
          onClear: page.onClear,
          onPutProfile: page.onPutProfile,
          onRemoveProfile: page.onRemoveProfile,
          onCopyCommand: page.onCopyCommand,
          onElsewhere: page.onElsewhere,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('quarantined'));
    await tester.tap(find.text('sessions'));
    await tester.tap(find.text('bacnet failed'));
    expect(tapped, ['quarantined', 'link:bacnet']);
  });
}
