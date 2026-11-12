import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/pages/history_page.dart';
import 'package:ui/tables/row_table.dart';

import 'trend.dart';

// The data of board `History` (design canvas, `canvas/History.dc.html`):
// the group `boiler-1` with t1 and t2 picked, its trend the board `Trend`
// mounts. The page around the trend is the app's History (docs/studio.md
// §7.7); only the trend follows spec trend.md.

const _base = 'wy/plant/downstream/plc1';

HistoryPage historyFrame() => HistoryPage(
  groupsLabel: 'WATCH GROUPS · 3',
  groups: const [
    GroupItemVm(
      id: 'boiler-1',
      title: 'boiler-1',
      sub: '5 points · on change · 90 d',
      selected: true,
    ),
    GroupItemVm(id: 'tank', title: 'tank', sub: '2 points · every 5 s · 30 d'),
    GroupItemVm(
      id: 'energy',
      title: 'energy',
      sub: '12 points · 15 min rollups · 5 y',
    ),
  ],
  onGroup: (_) {},
  onAddGroup: () {},
  title: 'boiler-1',
  subtitle: '5 points · on change',
  ranges: const [
    TabItemVm(id: '1h', label: '1 h'),
    TabItemVm(id: '24h', label: '24 h'),
    TabItemVm(id: '7d', label: '7 d'),
    TabItemVm(id: '30d', label: '30 d'),
  ],
  range: '24h',
  onRange: (_) {},
  trend: trendFrame('idle').vm,
  trendEmpty: 'Pick a point to see its trend',
  onTrendWindow: (_, _) {},
  pointsLabel: 'POINTS · 5',
  pointsHint: 'Click a point to see its trend; Ctrl-click adds one',
  columns: const [
    ColumnVm('Point', flex: 4),
    ColumnVm('Watch'),
    ColumnVm('Read rows', flex: 2),
  ],
  points: const [
    RowVm(
      id: '$_base/t1',
      selected: true,
      cells: [
        CellVm(title: 'downstream/plc1/t1', monospace: true),
        CellVm(title: 'w1', monospace: true),
        CellVm(title: '288'),
      ],
    ),
    RowVm(
      id: '$_base/t2',
      selected: true,
      cells: [
        CellVm(title: 'downstream/plc1/t2', monospace: true),
        CellVm(title: 'w2', monospace: true),
        CellVm(title: '288'),
      ],
    ),
    RowVm(
      id: '$_base/p1',
      cells: [
        CellVm(title: 'downstream/plc1/p1', monospace: true),
        CellVm(title: 'w3', monospace: true),
        CellVm(title: '—'),
      ],
    ),
    RowVm(
      id: '$_base/flow',
      cells: [
        CellVm(title: 'downstream/plc1/flow', monospace: true),
        CellVm(title: 'w4', monospace: true),
        CellVm(title: '—'),
      ],
    ),
    RowVm(
      id: '$_base/t3',
      cells: [
        CellVm(title: 'downstream/plc1/t3', monospace: true),
        CellVm(title: 'w5', monospace: true),
        CellVm(title: '—'),
      ],
    ),
  ],
  onPoint: (_, _) {},
  footer: 'Historian: redb, one file per UTC day · 1.9 GiB',
  inspector: const DetailInspectorVm(
    eyebrow: 'WATCH GROUP',
    title: 'boiler-1',
    keyName: 'sys/history/boiler-1',
    facts: [
      FactVm(label: 'Record', value: 'on change'),
      FactVm(label: 'Keep', value: '90 d'),
    ],
  ),
  onAction: (_) {},
);
