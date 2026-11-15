import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/catalog_card.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/pages/link_install_page.dart';

import 'frames/harness.dart';

/// Add a link, Choose step (owner 2026-11-11): every card as high as every
/// other with its bottom row at the same place, a version on each card the
/// broker gives one for, the official mark only where the broker says so
/// (ADR 0043 §5), the search field and the chips on one centre line.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  CatalogCardVm card(
    String id,
    String description, {
    String? version,
    int existing = 0,
    bool official = false,
  }) => CatalogCardVm(
    id: id,
    tag: id.toUpperCase(),
    name: id,
    description: description,
    builtIn: version != null,
    modes: const [
      LinkRunMode.embedded,
      LinkRunMode.process,
      LinkRunMode.external,
    ],
    version: version,
    existing: existing,
    official: official,
  );

  final cards = [
    card('mock', 'Generated points', version: 'wyrmd 0.1.0', existing: 1),
    card(
      'modbus',
      'TCP, RTU over TCP, serial RTU · master and slave, and a description '
          'long enough to need a second and a third line at any width',
      version: 'wyrmd 0.1.0',
    ),
    card('mqtt', '', version: 'wyrmd 0.1.0'),
    card('webdav', 'Nextcloud, ownCloud and other WebDAV servers'),
    card('ai', 'Plans changes for a person to approve'),
    card(
      'alarm',
      'Alarm classes, records and acknowledgement',
      official: true,
      existing: 1,
    ),
  ];

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(
        LinkInstallPage(
          vm: LinkInstallVm(
            site: 'plant',
            from: InstallFrom.official,
            steps: const [InstallStepKey.choose],
            step: InstallStepKey.choose,
            broker: 'plant',
            mode: LinkRunMode.embedded,
            categories: const ['Test', 'Equipment', 'File stores', 'Apps'],
            cards: cards,
          ),
          onClose: () {},
          onCategory: (_) {},
          onItem: (_) {},
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [1440.0, 1000.0, 760.0]) {
    testWidgets('every card is as high as every other at $width', (
      tester,
    ) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
      final heights = {
        for (final c in cards)
          tester.getSize(find.byKey(ValueKey('card:${c.id}'))).height,
      };
      expect(heights, hasLength(1), reason: '$heights');
      // The bottom row sits at the same place on each card.
      final gaps = {
        for (final c in cards)
          (tester.getBottomLeft(find.byKey(ValueKey('card:${c.id}'))).dy -
                  tester
                      .getBottomLeft(
                        find.text(c.modeCodes).at(cards.indexOf(c)),
                      )
                      .dy)
              .toStringAsFixed(1),
      };
      expect(gaps, hasLength(1), reason: '$gaps');
    });
  }

  testWidgets('a card shows its version when it has one', (tester) async {
    await pump(tester, 1440);
    expect(find.text('wyrmd 0.1.0'), findsNWidgets(3));
  });

  testWidgets('only a card the broker calls official has the mark', (
    tester,
  ) async {
    await pump(tester, 1440);
    expect(find.text('official'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('card:alarm')),
        matching: find.text('official'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the field and the chips share one height and one centre', (
    tester,
  ) async {
    await pump(tester, 1440);
    final field = find.byKey(const ValueKey('catalog-search'));
    final chip = find.byKey(const ValueKey('category:Equipment'));
    expect(tester.getSize(field).height, tester.getSize(chip).height);
    expect(tester.getCenter(field).dy, tester.getCenter(chip).dy);
  });

  testWidgets('on a narrow window the chips wrap under the field', (
    tester,
  ) async {
    await pump(tester, 600);
    expect(tester.takeException(), isNull);
    final field = find.byKey(const ValueKey('catalog-search'));
    final chip = find.byKey(const ValueKey('category:*'));
    expect(
      tester.getTopLeft(chip).dy,
      greaterThan(tester.getBottomLeft(field).dy),
    );
  });

  // The rights card's checkbox draws its ink on a Material of its own: in the
  // tinted card a bare ListTile threw on every frame (Studio fault,
  // 2026-11-13).
  testWidgets('the rights checkbox builds without a fault, and ticks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ticks = <bool>[];
    await tester.pumpWidget(
      frame(
        LinkInstallPage(
          vm: const LinkInstallVm(
            site: 'plant',
            from: InstallFrom.official,
            steps: [InstallStepKey.run],
            step: InstallStepKey.run,
            broker: 'plant',
            mode: LinkRunMode.embedded,
            name: 'bot',
            offersAccept: true,
          ),
          onClose: () {},
          onAccept: ticks.add,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(S.current.acceptRequestedRights));
    expect(ticks, [true]);
  });
}
