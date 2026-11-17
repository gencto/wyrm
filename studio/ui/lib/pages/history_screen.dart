import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../buttons/segmented_tabs.dart';
import '../charts/trend.dart';
import '../charts/trend_format.dart';
import '../containers/detail_inspector.dart';
import '../containers/fact_grid.dart';
import '../containers/side_panels.dart';
import '../indicators/app_icon.dart';
import '../models/disabled.dart';
import '../models/panels.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../tables/row_table.dart';
import 'history_page.dart';

// What History is drawn from (docs/studio.md §7.7), as typed values: the
// connector maps the domain into these; `HistoryScreen` words them in the
// language on screen and draws them with [HistoryPage] (studio-rules §3,
// §5).

/// A range of History's trend, as its tab says it.
enum HistorySpan {
  hour,
  day,
  week,
  month;

  String get label => switch (this) {
    hour => S.current.historyRange1h,
    day => S.current.historyRange24h,
    week => S.current.historyRange7d,
    month => S.current.historyRange30d,
  };
}

/// An action of History's inspector or of its `+`.
enum HistoryAct {
  /// `sys/history ▸ add_watch_group`.
  addGroup,

  /// The group's `add_watch_path`.
  addPath,

  /// The group's `edit`.
  edit,

  /// `sys/history ▸ purge`.
  purge,

  /// The group's `remove`.
  remove,

  /// The picked point's watch `unsubscribe`.
  unsubscribe,
}

/// How a watch group records.
enum GroupLogging {
  none,
  interval,
  allData,
  pointChange;

  String get label => switch (this) {
    none => S.current.logTypeNone,
    interval => S.current.logTypeInterval,
    allData => S.current.logTypeAllData,
    pointChange => S.current.logTypePointChange,
  };
}

/// A watch group: its name, how it records (null: not known yet), its
/// interval and flush (s) and its watches.
final class WatchGroupVm extends Equatable {
  const WatchGroupVm({
    required this.name,
    this.logging,
    this.interval,
    this.flush,
    this.points = const [],
  });

  final String name;
  final GroupLogging? logging;
  final num? interval;
  final num? flush;
  final List<WatchPointVm> points;

  @override
  List<Object?> get props => [name, logging, interval, flush, points];
}

/// One point a group records: its key, its watch's node name and, for a
/// point on the trend, the rows read for it.
final class WatchPointVm extends Equatable {
  const WatchPointVm({required this.key, required this.watch, this.rows});

  final String key;
  final String watch;
  final int? rows;

  @override
  List<Object?> get props => [key, watch, rows];
}

/// The historian's own values, as the broker gives them: its size in MiB
/// (or its text when that is not a number), its series, the days raw rows
/// are kept, the rows written and the oldest day.
final class HistorianStatsVm extends Equatable {
  const HistorianStatsVm({
    this.sizeMib,
    this.size,
    this.series,
    this.keepDays,
    this.rowsWritten,
    this.oldestDay,
  });

  final num? sizeMib;
  final String? size;
  final String? series;
  final String? keepDays;
  final String? rowsWritten;
  final String? oldestDay;

  @override
  List<Object?> get props => [
    sizeMib,
    size,
    series,
    keepDays,
    rowsWritten,
    oldestDay,
  ];
}

/// The picked points' trend (spec trend.md §4): their series, the range
/// and the window (µs), the step drawn (null: raw rows).
final class HistoryTrendVm extends Equatable {
  const HistoryTrendVm({
    required this.series,
    required this.rangeStart,
    required this.rangeEnd,
    required this.windowStart,
    required this.windowEnd,
    this.step,
    this.minWindow = 0,
    this.following = true,
    this.loading = false,
    this.refining = false,
  });

  final List<TrendSeriesVm> series;
  final int rangeStart;
  final int rangeEnd;
  final int windowStart;
  final int windowEnd;
  final Duration? step;
  final int minWindow;
  final bool following;
  final bool loading;
  final bool refining;

  @override
  List<Object?> get props => [
    series,
    rangeStart,
    rangeEnd,
    windowStart,
    windowEnd,
    step,
    minWindow,
    following,
    loading,
    refining,
  ];
}

/// What History draws.
final class HistoryScreenVm extends Equatable {
  const HistoryScreenVm({
    required this.groups,
    required this.span,
    required this.picked,
    this.selected,
    this.stats = const HistorianStatsVm(),
    this.trend,
    this.watch,
    this.disabled,
    this.panels = const SidePanelWidths(),
  });

  final List<WatchGroupVm> groups;

  /// The group picked, by name.
  final String? selected;
  final HistorianStatsVm stats;
  final HistorySpan span;

  /// The points on the trend (a ⌘- or Ctrl-click toggles one).
  final ToggleVm<String> picked;
  final HistoryTrendVm? trend;

  /// The watch of the one point picked: Stop recording works on it.
  final String? watch;

  /// What the user lacks to change `sys/history`.
  final Disabled? disabled;

  /// The groups and inspector widths the viewer chose.
  final SidePanelWidths panels;

  @override
  List<Object?> get props => [
    groups,
    selected,
    stats,
    span,
    picked,
    trend,
    watch,
    disabled,
    panels,
  ];
}

/// History from typed values: it words them in the language on screen and
/// draws them with [HistoryPage].
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    required this.vm,
    required this.onGroup,
    required this.onSpan,
    required this.onPick,
    required this.onAct,
    required this.onTrendWindow,
    required this.onTrendToggle,
    required this.onTrendReset,
    required this.onPanelWidth,
    super.key,
  });

  final HistoryScreenVm vm;

  /// A group picked, by name.
  final ValueChanged<String> onGroup;
  final ValueChanged<HistorySpan> onSpan;

  /// A plain click on a point: the trend shows it alone.
  final ValueChanged<String> onPick;
  final ValueChanged<HistoryAct> onAct;

  /// The trend's window (µs), its legend toggles and `Reset zoom`.
  final RangeChanged<int> onTrendWindow;
  final ValueChanged<String> onTrendToggle;
  final VoidCallback onTrendReset;
  final PanelResized onPanelWidth;

  /// `every 5 s`; empty for none.
  static String _every(num? s) => s == null
      ? ''
      : S.current.everySeconds(s == s.truncate() ? s.toInt() : s);

  /// `2 points · Point Change · every 5 s`.
  static String _about(WatchGroupVm g) => [
    S.current.pointsCount(g.points.length),
    g.logging?.label ?? '',
    _every(g.interval),
  ].where((s) => s.isNotEmpty).join(' · ');

  String get _footer {
    final st = vm.stats;
    return [
      if (st.sizeMib case final n?)
        S.current.historianSize(Formats.mebibytes(n))
      else if (st.size case final s?)
        S.current.historianSize(s),
      if (st.series case final s?) S.current.historianSeries(s),
      if (st.keepDays case final s?) S.current.historianKeep(s),
    ].join(' · ');
  }

  TrendVm? get _trend {
    final t = vm.trend;
    if (t == null) {
      return null;
    }
    return TrendVm(
      title: [for (final s in t.series) s.name].join(', '),
      series: t.series,
      rangeStart: t.rangeStart,
      rangeEnd: t.rangeEnd,
      windowStart: t.windowStart,
      windowEnd: t.windowEnd,
      rollup: trendRollup(t.step),
      step: t.step?.inMicroseconds,
      minWindow: t.minWindow,
      endsNow: true,
      following: t.following,
      loading: t.loading,
      refining: t.refining,
      format: trendFormat(),
    );
  }

  DetailInspectorVm<HistoryAct>? _inspector(WatchGroupVm? g) {
    if (g == null) {
      return null;
    }
    final off = vm.disabled?.text;
    ActionRowVm<HistoryAct> row(
      HistoryAct act,
      AppIcon icon,
      String title,
      String note,
      String code, {
      Tone tone = Tone.neutral,
    }) => ActionRowVm(
      id: act,
      icon: icon,
      title: title,
      description: note,
      code: code,
      tone: tone,
      disabledReason: off,
    );
    final picked = vm.picked.selected;
    return DetailInspectorVm(
      eyebrow: S.current.watchGroup,
      title: g.name,
      keyName: 'sys/history/${g.name}',
      facts: [
        if (g.logging case final how?)
          FactVm(label: S.current.factRecord, value: how.label),
        if (g.interval != null)
          FactVm(label: S.current.factInterval, value: _every(g.interval)),
        if (g.flush != null)
          FactVm(label: S.current.factFlush, value: _every(g.flush)),
        if (vm.stats.rowsWritten case final r?)
          FactVm(label: S.current.factRowsWritten, value: r),
        if (vm.stats.oldestDay case final d?)
          FactVm(label: S.current.factOldest, value: d),
      ],
      groups: [
        if (vm.watch != null && picked.length == 1)
          ActionGroupVm(
            label: picked.single.split('/').last,
            actions: [
              row(
                HistoryAct.unsubscribe,
                AppIcon.actionTrash,
                S.current.stopRecording,
                S.current.unsubscribeNote,
                'unsubscribe',
                tone: Tone.warn,
              ),
            ],
          ),
        ActionGroupVm(
          label: S.current.groupChange,
          actions: [
            row(
              HistoryAct.addPath,
              AppIcon.uiAdd,
              S.current.addWatchPath,
              S.current.addWatchPathNote,
              'add_watch_path',
            ),
            row(
              HistoryAct.edit,
              AppIcon.actionEdit,
              S.current.editGroup,
              S.current.editGroupNote,
              'edit',
            ),
          ],
        ),
        ActionGroupVm(
          label: S.current.groupRemove,
          actions: [
            row(
              HistoryAct.purge,
              AppIcon.actionTrash,
              S.current.purgeHistory,
              S.current.purgeHistoryNote,
              'purge',
              tone: Tone.warn,
            ),
            row(
              HistoryAct.remove,
              AppIcon.actionTrash,
              S.current.removeGroup,
              S.current.removeGroupNote,
              'remove',
              tone: Tone.bad,
            ),
          ],
        ),
      ],
      footer: S.current.historyFooter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = vm.groups.where((g) => g.name == vm.selected).firstOrNull;
    return HistoryPage<HistorySpan, HistoryAct>(
      groupsLabel: S.current.watchGroups(vm.groups.length),
      groups: [
        for (final x in vm.groups)
          GroupItemVm(
            id: x.name,
            title: x.name,
            sub: _about(x),
            selected: x.name == vm.selected,
          ),
      ],
      onGroup: onGroup,
      onAddGroup: () => onAct(HistoryAct.addGroup),
      addReason: vm.disabled?.text,
      title: g?.name,
      subtitle: g == null ? null : _about(g),
      empty: S.current.noWatchGroups,
      ranges: [
        for (final s in HistorySpan.values) TabItemVm(id: s, label: s.label),
      ],
      range: vm.span,
      onRange: onSpan,
      trend: _trend,
      trendEmpty: S.current.pickPointTrend,
      onTrendWindow: onTrendWindow,
      onTrendToggle: onTrendToggle,
      onTrendReset: onTrendReset,
      pointsLabel: S.current.pointsCount(g?.points.length ?? 0),
      pointsHint: S.current.pickPointHint,
      columns: [
        ColumnVm(S.current.colPoint, flex: 4),
        ColumnVm(S.current.colWatch),
        ColumnVm(S.current.colReadRows, flex: 2),
      ],
      points: [
        for (final p in g?.points ?? const <WatchPointVm>[])
          RowVm(
            id: p.key,
            selected: vm.picked.contains(p.key),
            cells: [
              CellVm(
                title: p.key.split('/').skip(2).join('/'),
                monospace: true,
              ),
              CellVm(title: p.watch, monospace: true),
              // Read only for a picked point: a count of the others would
              // cost a history read each.
              CellVm(title: p.rows == null ? '—' : '${p.rows}'),
            ],
          ),
      ],
      picked: vm.picked,
      onPick: onPick,
      pointsEmpty: S.current.noWatchPaths,
      footer: _footer,
      inspector: _inspector(g),
      onAction: onAct,
      panels: vm.panels,
      onPanelWidth: onPanelWidth,
    );
  }
}
