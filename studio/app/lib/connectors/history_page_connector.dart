import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/follow_history_action.dart';
import 'package:business/redux/historian/actions/pick_range_action.dart';
import 'package:business/redux/historian/actions/pick_trend_point_action.dart';
import 'package:business/redux/historian/actions/set_selected_action.dart';
import 'package:business/redux/historian/actions/set_trend_window_action.dart';
import 'package:business/redux/historian/actions/show_history_action.dart';
import 'package:business/redux/historian/actions/toggle_trend_series_action.dart';
import 'package:business/redux/historian/actions/zoom_history_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/historian_stats.dart';
import 'package:business/wyrm/history_trend.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/models/panels.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/history_screen.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../common/side_panels.dart';
import '../common/tab_visibility.dart';
import '../dialogs/history_dialogs.dart';
import '../mappers/history_mappers.dart';
import '../mappers/rights_mappers.dart';

/// History (docs/studio.md §7.7): the watch groups of `sys/history`, the
/// picked points' trend (computed in business, `historyTrend`), mapped
/// through `app/lib/mappers/history_mappers.dart`; `HistoryScreen` words
/// them. One action per intent; an action of the inspector opens its form
/// from the widget, with the widget's context (`askHistory`).
@RoutePage()
class HistoryPageConnector extends StatelessWidget {
  const HistoryPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: HistoryScreen(
        vm: vm.screen,
        onGroup: vm.onGroup,
        onSpan: vm.onSpan,
        onPick: vm.onPick,
        onAct: (act) => unawaited(askHistory(context, act)),
        onTrendWindow: (start, end) =>
            vm.onTrendWindow(TrendWindow(start, end)),
        onTrendToggle: vm.onTrendToggle,
        onTrendReset: vm.onTrendReset,
        onPanelWidth: (side, width) => vm.onPanelWidth(PanelWidth(side, width)),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, HistoryPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final series = historian.series;
    return _Vm(
      screen: HistoryScreenVm(
        groups: [for (final g in historian.shownGroups) g.vm(series)],
        selected: historian.selected,
        stats: historianStats.vm,
        span: historian.range.tab,
        picked: ToggleVm(
          selected: historian.points.toISet(),
          onToggle: (key, {required on}) =>
              dispatch(PickTrendPointAction(key, add: true)),
        ),
        trend: historyTrend?.vm,
        watch: pickedWatch,
        disabled: site.lacks(Perm.config, '${site.root}/sys/history')?.disabled,
        panels: WorkspacePanels.history.widths(panels.widths),
      ),
      onShow: () => dispatch(ShowHistoryAction()),
      onHide: () => dispatchSync(FollowHistoryAction(show: false)),
      onGroup: (name) => dispatchSync(SetSelectedAction(name)),
      onSpan: (s) => dispatch(PickRangeAction(s.range)),
      onPick: (key) => dispatch(PickTrendPointAction(key)),
      onTrendWindow: (w) => dispatchSync(ZoomHistoryAction(w.start, w.end)),
      onTrendToggle: (k) => dispatchSync(ToggleTrendSeriesAction(k)),
      onTrendReset: () => dispatchSync(SetTrendWindowAction(null)),
      onPanelWidth: (p) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.history.slot(p.side), p.width),
      ),
    );
  }
}

/// What History draws ([screen], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.screen,
    required this.onShow,
    required this.onHide,
    required this.onGroup,
    required this.onSpan,
    required this.onPick,
    required this.onTrendWindow,
    required this.onTrendToggle,
    required this.onTrendReset,
    required this.onPanelWidth,
  }) : super(equals: [screen]);

  final HistoryScreenVm screen;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onGroup;
  final ValueChanged<HistorySpan> onSpan;
  final ValueChanged<String> onPick;
  final ValueChanged<TrendWindow> onTrendWindow;
  final ValueChanged<String> onTrendToggle;
  final VoidCallback onTrendReset;
  final ValueChanged<PanelWidth> onPanelWidth;
}
