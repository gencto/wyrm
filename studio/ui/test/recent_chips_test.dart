import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/models/gateway_note.dart';

import 'frames/harness.dart';
import 'frames/login.dart';

/// docs/design/specs/login.md §3.2 "Gateway labels": gateways on one host
/// are told apart by their port, on the chips and in the status line.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('five gateways on one host: five chips, each its port', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(loginOneHost()));
    await tester.pump();

    final chips = tester.widgetList<RecentChip>(find.byType(RecentChip));
    expect([for (final c in chips) c.vm.label], oneHostLabels);
    for (final l in oneHostLabels) {
      expect(
        find.descendant(of: find.byType(RecentChip), matching: find.text(l)),
        findsOneWidget,
      );
    }
    expect(find.text('No answer from 127.0.0.1:8446'), findsOneWidget);
    expect(
      [for (final c in chips) c.vm.current],
      [false, false, true, false, false],
    );
  });

  test('the status line is said in ui', () async {
    await S.load(const Locale('en'));
    expect(
      const GatewayNote.answered('127.0.0.1:8445', 12).text,
      '127.0.0.1:8445 · answered in 12 ms',
    );
    expect(
      const GatewayNote.noAnswer('plant').text,
      'No answer from plant',
    );
    expect(
      const GatewayNote.picked('lab').text,
      'lab · picked from this network',
    );
    expect(
      const GatewayNote.pickedWithStandby('lab').text,
      'lab · picked from this network · standby filled in',
    );
    expect(
      const GatewayNote.typeOrFind().text,
      'Type the address, or find one on this network.',
    );
  });
}
