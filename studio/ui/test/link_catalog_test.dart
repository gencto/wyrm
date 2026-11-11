import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/containers/catalog_card.dart';
import 'package:ui/indicators/step_rail.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/link_install_page.dart';

import 'frames/harness.dart';

/// Add a link, Choose step (owner 2026-11-11): every card as high as every
/// other with its bottom row at the same place, a version on each card the
/// broker gives one for, the official mark only where the broker says so
/// (ADR 0043 §5), the search field and the chips on one centre line.
void main() {
  const labels = InstallLabels(
    crumb: 'Links',
    title: 'Add a link',
    needs: '',
    railLabel: 'STEPS',
    railNote: '',
    stepOf: 'STEP 1 OF 4',
    question: 'What do you want to connect?',
    why: '',
    answersTitle: '',
    answersNote: '',
    back: 'Back',
    next: 'Next',
    onBroker: '',
    howItRuns: '',
    linkName: '',
    accept: '',
    checkedHere: '',
    manifest: '',
  );

  CatalogCardVm card(
    String id,
    String description, {
    String? version,
    String? note,
    String? official,
  }) => CatalogCardVm(
    id: id,
    tag: id.toUpperCase(),
    name: id,
    description: description,
    source: version == null ? 'package' : 'built in',
    builtIn: version != null,
    modes: 'embedded · process · external',
    version: version,
    note: note,
    official: official,
  );

  final cards = [
    card('mock', 'Generated points', version: 'wyrmd 0.1.0', note: '1 link'),
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
      official: 'official',
      note: '1 link',
    ),
  ];

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(
        LinkInstallPage(
          labels: labels,
          steps: const [StepVm(title: 'Choose', sub: 'now')],
          step: 0,
          answers: const [],
          onClose: () {},
          catalog: CatalogPartVm(
            categories: const [
              'All',
              'Test',
              'Equipment',
              'File stores',
              'Apps',
            ],
            category: 'All',
            cards: cards,
            note: '',
            query: FieldVm(value: null, onChanged: (_) {}),
            searchHint: 'Search the list',
          ),
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
                      .getBottomLeft(find.text(c.modes).at(cards.indexOf(c)))
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
    final chip = find.byKey(const ValueKey('category:All'));
    expect(
      tester.getTopLeft(chip).dy,
      greaterThan(tester.getBottomLeft(field).dy),
    );
  });
}
