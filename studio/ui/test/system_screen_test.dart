import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/system_data.dart';
import 'package:ui/pages/system_page.dart';
import 'package:ui/pages/system_screen.dart';

import 'frames/harness.dart';

/// The card *Broker version* of System › Maintenance as `SystemScreen`
/// words it. Behind `Features.brokerUpdate` (off) no screen shows it, so
/// its states are checked here.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  void none() {}

  Future<BrokerVersionCardVm?> card(
    WidgetTester t,
    SysVersionData v, {
    Disabled? reason,
  }) async {
    t.view.physicalSize = const Size(1364, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      frame(
        SystemScreen(
          vm: SystemScreenVm(
            site: 'plant',
            tab: SysTab.maintenance,
            maintenance: SysMaintData(version: v, reason: reason),
          ),
          onTab: (_) {},
          onTile: (_) {},
          onAttention: (_) {},
          onMeasure: (_) {},
          onTrafficWindow: (_, _) {},
          onTrafficFollow: none,
          onTrafficReset: none,
          onBanner: none,
          onGuide: (_) {},
          onSource: (_) {},
          onLevel: (_) {},
          onFilter: (_) {},
          onLines: (_) {},
          onAround: (_) {},
          onAuto: (_) {},
          onGetLog: none,
          onCopyLog: none,
          onSaveLog: none,
          onLogLevel: (_) {},
          onClear: none,
          onPutProfile: none,
          onRemoveProfile: (_) {},
          onCopyCommand: (_) {},
          onBrokerUpdate: none,
          onBackUp: none,
          onRestore: none,
          onOpenBackup: (_) {},
          onElsewhere: (_) {},
        ),
      ),
    );
    return t.widget<SystemPage>(find.byType(SystemPage)).maintenance.version;
  }

  testWidgets('the current release: neutral, Show', (t) async {
    final c = await card(
      t,
      const SysVersionData(version: '0.2.0', latest: '0.2.0'),
    );
    expect(c?.line, S.current.bupCardCurrent('0.2.0'));
    expect(c?.tone, Tone.neutral);
    expect(c?.action, S.current.bupShow);
  });

  testWidgets('a newer release: ember, Update', (t) async {
    final c = await card(
      t,
      const SysVersionData(version: '0.1.0', latest: '0.2.0', newer: true),
    );
    expect(c?.line, S.current.bupCardAvailable('0.1.0', '0.2.0'));
    expect(c?.tone, Tone.ember);
    expect(c?.action, S.current.bupUpdate);
  });

  testWidgets('on trial with a newer release: ember, Show while it runs', (
    t,
  ) async {
    final c = await card(
      t,
      const SysVersionData(
        version: '0.1.0',
        latest: '0.2.0',
        state: SysSelfUpdate.trial,
        newer: true,
        runs: true,
      ),
    );
    expect(c?.line, S.current.bupCardTrial('0.1.0'));
    expect(c?.tone, Tone.ember);
    expect(c?.action, S.current.bupShow);
  });

  testWidgets('rolled back: warn, and the reason disables it', (t) async {
    final c = await card(
      t,
      const SysVersionData(
        version: '0.1.0',
        latest: '0.2.0',
        state: SysSelfUpdate.rolledBack,
        newer: true,
        runs: true,
      ),
      reason: const NeedsLevel(AccessLevel.config, 'sys'),
    );
    expect(c?.line, S.current.bupCardRolledBack('0.1.0'));
    expect(c?.tone, Tone.warn);
    expect(c?.action, S.current.bupShow);
    expect(c?.reason, 'needs config on sys');
  });
}
