import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/containers/inspector.dart';
import 'package:ui/overlays/node_menu.dart';

import 'frames/explorer.dart';
import 'frames/harness.dart';

/// A display name is user text and can be a sentence, a key segment can
/// be 50 characters: no title, header or label may overflow
/// (docs/design/specs/explorer.md §3). A RenderFlex overflow fails these.
void main() {
  for (final width in [1440.0, 1100.0, 900.0, 760.0]) {
    testWidgets('Explorer with a long name at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame(explorerLongName()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(frame(explorerFlow()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the node menu header of a long name', (tester) async {
    await tester.pumpWidget(
      frame(
        Center(
          child: NodeMenu(
            vm: const NodeMenuVm(
              title: 'supply_air_temperature_controller_north_wing_floor_2',
              subtitle: 'modbus device · 11 actions',
              groups: [
                NodeMenuGroupVm(
                  label: 'Configure · staged, applied on review and apply',
                  items: [
                    NodeMenuItemVm(
                      id: 'edit',
                      label: 'Edit the device parameters and its polling plan…',
                      level: 'config',
                    ),
                  ],
                ),
              ],
            ),
            onPick: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('the inspector title of a long display name', (tester) async {
    await tester.pumpWidget(
      frame(
        const Row(
          children: [
            Spacer(),
            Inspector(
              eyebrow: 'Dataflow',
              title:
                  'ahu2: count mod 10 × 10 → mockdev knob on change; temp in '
                  '°F; a warm flag, and more words than fit in two lines',
              width: 320,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
