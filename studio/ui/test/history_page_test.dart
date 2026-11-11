import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/pages/history_page.dart';
import 'package:ui/tables/row_table.dart';

import 'frames/harness.dart';

/// History: a click on a point picks it for the trend (⌘/Ctrl adds it); it
/// runs no action. With no point picked the trend says how to get one.
void main() {
  Future<(List<(String, bool)>, List<String>)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picks = <(String, bool)>[];
    final actions = <String>[];
    await tester.pumpWidget(
      frame(
        HistoryPage(
          groupsLabel: 'WATCH GROUPS',
          groups: const [GroupItemVm(id: 'ahu', title: 'ahu', sub: '2 points')],
          onGroup: (_) {},
          onAddGroup: () {},
          title: 'ahu',
          ranges: const [TabItemVm(id: '24h', label: '24 h')],
          range: '24h',
          onRange: (_) {},
          trend: const [],
          trendLabels: const ('', ''),
          trendEmpty: 'Pick a point to see its trend',
          pointsLabel: '2 POINTS',
          pointsHint: 'Click a point to see its trend',
          columns: const [ColumnVm('Point'), ColumnVm('Watch')],
          points: const [
            RowVm(
              id: 'wy/c/downstream/m/a',
              cells: [CellVm(title: 'downstream/m/a')],
            ),
            RowVm(
              id: 'wy/c/downstream/m/b',
              cells: [CellVm(title: 'downstream/m/b')],
            ),
          ],
          onPoint: (id, add) => picks.add((id, add)),
          onAction: actions.add,
        ),
      ),
    );
    return (picks, actions);
  }

  testWidgets('no point picked: the trend says to pick one', (tester) async {
    await pump(tester);
    expect(find.text('Pick a point to see its trend'), findsOneWidget);
    expect(find.text('Click a point to see its trend'), findsOneWidget);
  });

  testWidgets('a click picks, a ⌘-click adds, neither runs an action', (
    tester,
  ) async {
    final (picks, actions) = await pump(tester);
    await tester.tap(find.text('downstream/m/a'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('downstream/m/b'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(picks, [
      ('wy/c/downstream/m/a', false),
      ('wy/c/downstream/m/b', true),
    ]);
    expect(actions, isEmpty);
  });
}
