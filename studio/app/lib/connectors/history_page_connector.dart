import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/pick_point_action.dart';
import 'package:business/redux/historian/actions/retrieve_historian_action.dart';
import 'package:business/redux/historian/actions/retrieve_series_action.dart';
import 'package:business/redux/historian/actions/set_range_action.dart';
import 'package:business/redux/historian/actions/set_selected_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/charts/trend_chart.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/history_page.dart';
import 'package:ui/tables/row_table.dart';

import '../common/side_panels.dart';
import '../common/tab_visibility.dart';
import '../dialogs/node_action_dialog.dart';

@RoutePage()
class HistoryPageConnector extends StatelessWidget {
  const HistoryPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: () {},
      child: HistoryPage(
        groupsLabel: S.current.watchGroups(vm.groups.length),
        groups: vm.groups,
        onGroup: vm.onGroup,
        onAddGroup: () => vm.onAction(context, 'add_group'),
        addReason: vm.configReason,
        title: vm.title,
        subtitle: vm.subtitle,
        empty: S.current.noWatchGroups,
        ranges: const [
          TabItemVm(id: '1h', label: '1 h'),
          TabItemVm(id: '24h', label: '24 h'),
          TabItemVm(id: '7d', label: '7 d'),
          TabItemVm(id: '30d', label: '30 d'),
        ],
        range: vm.range,
        onRange: vm.onRange,
        trend: vm.trend,
        trendLabels: vm.trendLabels,
        trendEmpty: vm.picked ? S.current.noHistory : S.current.pickPointTrend,
        pointsLabel: S.current.pointsCount(vm.points.length),
        pointsHint: S.current.pickPointHint,
        columns: [
          ColumnVm(S.current.colPoint, flex: 4),
          ColumnVm(S.current.colWatch),
          ColumnVm(S.current.colReadRows, flex: 2),
        ],
        points: vm.points,
        onPoint: vm.onPoint,
        pointsEmpty: S.current.noWatchPaths,
        footer: vm.footer,
        inspector: vm.inspector,
        onAction: (a) => vm.onAction(context, a),
        panels: vm.panelWidths,
        onPanelWidth: vm.onPanelWidth,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, HistoryPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _base => '${site.root}/sys/history';

  @override
  _Vm fromStore() {
    final h = historian;
    final g = h.groups.where((g) => g.name == h.selected).firstOrNull;
    final stats = h.stats;
    // The one point picked: Stop recording works on its watch.
    final watch = g != null && h.points.length == 1
        ? switch (g.keys.indexOf(h.points.first)) {
            -1 => null,
            final i => g.watchIds[i],
          }
        : null;
    String every(num? s) => s == null
        ? ''
        : S.current.everySeconds(s == s.truncate() ? s.toInt() : s);
    return _Vm(
      panelWidths: WorkspacePanels.history.widths(panels.widths),
      onPanelWidth: (side, w) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.history.slot(side), w),
      ),
      configReason: site.needs('config', _base),
      groups: [
        for (final x in h.groups)
          GroupItemVm(
            id: x.name,
            title: x.name,
            sub: [
              S.current.pointsCount(x.keys.length),
              x.loggingType,
              every(x.interval),
            ].where((s) => s.isNotEmpty).join(' · '),
            selected: x.name == h.selected,
          ),
      ],
      title: g?.name,
      subtitle: g == null
          ? null
          : [
              S.current.pointsCount(g.keys.length),
              g.loggingType,
              every(g.interval),
            ].where((s) => s.isNotEmpty).join(' · '),
      range: h.range,
      picked: h.points.isNotEmpty,
      trend: [
        if (g != null)
          for (final k in h.points)
            if (h.series[k] case final s?)
              TrendSeriesVm(
                label: k.split('/').last,
                points: [
                  for (final p in s)
                    if (p.value case final v?)
                      (p.time.millisecondsSinceEpoch, v.toDouble()),
                ],
              ),
      ],
      trendLabels: () {
        final all = [for (final s in h.series.values) ...s];
        if (all.isEmpty) {
          return ('', '');
        }
        all.sort((a, b) => a.time.compareTo(b.time));
        return (_hm(all.first.time), _hm(all.last.time));
      }(),
      points: [
        if (g != null)
          for (final (i, k) in g.keys.indexed)
            RowVm(
              id: k,
              selected: h.points.contains(k),
              cells: [
                CellVm(title: k.split('/').skip(2).join('/'), monospace: true),
                CellVm(title: g.watchIds[i], monospace: true),
                // Read only for a picked point: a count of the others would
                // cost a history read each.
                CellVm(
                  title: switch (h.series[k]) {
                    final s? => '${s.length}',
                    null => '—',
                  },
                ),
              ],
            ),
      ],
      footer: [
        if (stats['database_size'] case final s?)
          S.current.historianSize(_mib(s)),
        if (stats['series'] case final s?) S.current.historianSeries(s),
        if (stats['retention_days'] case final s?) S.current.historianKeep(s),
      ].join(' · '),
      inspector: g == null
          ? null
          : DetailInspectorVm(
              eyebrow: S.current.watchGroup,
              title: g.name,
              keyName: 'sys/history/${g.name}',
              facts: [
                FactVm(label: S.current.factRecord, value: g.loggingType),
                if (g.interval != null)
                  FactVm(
                    label: S.current.factInterval,
                    value: every(g.interval),
                  ),
                if (g.flush != null)
                  FactVm(label: S.current.factFlush, value: every(g.flush)),
                if (stats['rows_written'] case final r?)
                  FactVm(label: S.current.factRowsWritten, value: r),
                if (stats['oldest_day'] case final d?)
                  FactVm(label: S.current.factOldest, value: d),
              ],
              groups: [
                if (watch != null)
                  ActionGroupVm(
                    label: h.points.first.split('/').last,
                    actions: [
                      ActionRowVm(
                        id: 'watch:$watch',
                        icon: 'action_trash',
                        title: S.current.stopRecording,
                        description: S.current.unsubscribeNote,
                        code: 'unsubscribe',
                        tone: Tone.warn,
                        disabledReason: site.needs('config', _base),
                      ),
                    ],
                  ),
                ActionGroupVm(
                  label: S.current.groupChange,
                  actions: [
                    ActionRowVm(
                      id: 'add_path',
                      icon: 'ui_add',
                      title: S.current.addWatchPath,
                      description: S.current.addWatchPathNote,
                      code: 'add_watch_path',
                      disabledReason: site.needs('config', _base),
                    ),
                    ActionRowVm(
                      id: 'edit',
                      icon: 'action_edit',
                      title: S.current.editGroup,
                      description: S.current.editGroupNote,
                      code: 'edit',
                      disabledReason: site.needs('config', _base),
                    ),
                  ],
                ),
                ActionGroupVm(
                  label: S.current.groupRemove,
                  actions: [
                    ActionRowVm(
                      id: 'purge',
                      icon: 'action_trash',
                      title: S.current.purgeHistory,
                      description: S.current.purgeHistoryNote,
                      code: 'purge',
                      tone: Tone.warn,
                      disabledReason: site.needs('config', _base),
                    ),
                    ActionRowVm(
                      id: 'remove',
                      icon: 'action_trash',
                      title: S.current.removeGroup,
                      description: S.current.removeGroupNote,
                      code: 'remove',
                      tone: Tone.bad,
                      disabledReason: site.needs('config', _base),
                    ),
                  ],
                ),
              ],
              footer: S.current.historyFooter,
            ),
      onShow: () => unawaited(_load()),
      onGroup: (id) => dispatchSync(SetSelectedAction(id)),
      onPoint: (key, add) {
        dispatchSync(PickPointAction(key, add: add));
        unawaited(dispatchAndWait(RetrieveSeriesAction()));
      },
      onRange: (r) {
        dispatchSync(SetRangeAction(r));
        unawaited(dispatchAndWait(RetrieveSeriesAction()));
      },
      onAction: (context, a) async {
        if (await _run(context, a, '$_base/${g?.name}')) {
          await _load();
        }
      },
    );
  }

  Future<bool> _run(BuildContext context, String a, String group) {
    switch (a) {
      case 'add_group':
        return runNodeAction(context, _base, 'add_watch_group');
      case 'add_path':
        return runNodeAction(context, group, 'add_watch_path');
      case 'edit':
        return runNodeAction(context, group, 'edit');
      case 'remove':
        return runNodeAction(
          context,
          group,
          'remove',
          confirm: S.current.removeGroupNote,
        );
      case 'purge':
        return runNodeAction(context, _base, 'purge');
      case _ when a.startsWith('watch:'):
        return runNodeAction(
          context,
          '$group/${a.substring(6)}',
          'unsubscribe',
          confirm: S.current.unsubscribeNote,
        );
    }
    return Future.value(false);
  }

  /// The groups and their points; recorded values only for the points
  /// picked (none on a first open).
  Future<void> _load() async {
    await dispatchAndWait(RetrieveHistorianAction());
    if (historian.points.isNotEmpty) {
      await dispatchAndWait(RetrieveSeriesAction());
    }
  }

  static String _hm(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.month}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  /// `database_size` is in MiB.
  static String _mib(String s) {
    final n = num.tryParse(s);
    if (n == null) {
      return s;
    }
    return n >= 1024
        ? '${(n / 1024).toStringAsFixed(1)} GiB'
        : '${n.toStringAsFixed(n < 10 ? 1 : 0)} MiB';
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.configReason,
    required this.groups,
    required this.title,
    required this.subtitle,
    required this.range,
    required this.picked,
    required this.trend,
    required this.trendLabels,
    required this.points,
    required this.footer,
    required this.inspector,
    required this.onShow,
    required this.onGroup,
    required this.onPoint,
    required this.onRange,
    required this.onAction,
    required this.panelWidths,
    required this.onPanelWidth,
  }) : super(
         equals: [
           configReason,
           groups,
           title,
           subtitle,
           range,
           picked,
           trend,
           trendLabels,
           points,
           footer,
           inspector,
           panelWidths,
         ],
       );

  final String? configReason;
  final List<GroupItemVm> groups;
  final String? title;
  final String? subtitle;
  final String range;

  /// A point is picked for the trend.
  final bool picked;
  final List<TrendSeriesVm> trend;
  final (String, String) trendLabels;
  final List<RowVm> points;
  final String footer;
  final DetailInspectorVm? inspector;
  final VoidCallback onShow;
  final ValueChanged<String> onGroup;

  /// A point row was clicked; `add` with ⌘/Ctrl held.
  final void Function(String key, bool add) onPoint;
  final ValueChanged<String> onRange;
  final Future<void> Function(BuildContext context, String action) onAction;
  final SidePanelWidths panelWidths;
  final void Function(PanelSide side, double width) onPanelWidth;
}
