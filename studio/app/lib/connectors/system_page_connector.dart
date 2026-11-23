import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/retrieve_backups_action.dart';
import 'package:business/redux/system/actions/change_log_query_action.dart';
import 'package:business/redux/system/actions/clear_conns_action.dart';
import 'package:business/redux/system/actions/copy_log_action.dart';
import 'package:business/redux/system/actions/copy_text_action.dart';
import 'package:business/redux/system/actions/follow_traffic_action.dart';
import 'package:business/redux/system/actions/hide_system_action.dart';
import 'package:business/redux/system/actions/open_system_tab_action.dart';
import 'package:business/redux/system/actions/poll_system_log_action.dart';
import 'package:business/redux/system/actions/remove_profile_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/redux/system/actions/set_around_action.dart';
import 'package:business/redux/system/actions/set_auto_action.dart';
import 'package:business/redux/system/actions/set_filter_action.dart';
import 'package:business/redux/system/actions/set_lines_action.dart';
import 'package:business/redux/system/actions/set_log_level_action.dart';
import 'package:business/redux/system/actions/set_measure_action.dart';
import 'package:business/redux/system/actions/set_source_action.dart';
import 'package:business/redux/system/actions/set_traffic_window_action.dart';
import 'package:business/redux/system/actions/show_system_action.dart';
import 'package:business/redux/system/actions/stage_log_level_action.dart';
import 'package:business/redux/system/actions/zoom_traffic_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/attention_item.dart';
import 'package:models/peer_kind.dart';
import 'package:models/sys_status.dart';
import 'package:models/sys_value.dart';
import 'package:models/system_notice.dart';
import 'package:models/traffic_measure.dart';
import 'package:ui/pages/system_data.dart';
import 'package:ui/pages/system_screen.dart';

import '../common/every.dart';
import '../common/save_log_action.dart';
import '../common/tab_visibility.dart';
import '../dialogs/backup_dialogs.dart';
import '../dialogs/broker_update_dialog.dart';
import '../dialogs/profile_dialog.dart';
import '../mappers/rights_mappers.dart';
import '../mappers/system_mappers.dart';
import '../navigation/system_place.dart';

/// System (specs/system.md): the broker's own page. The connector reads
/// selectors, maps the domain through `app/lib/mappers/system_mappers.dart`
/// into typed values (`SystemScreen` words them) and starts one action per
/// intent. Its dialogs (a backup, the broker's update, a profile to put)
/// open from the widget, with the widget's context.
@RoutePage()
class SystemPageConnector extends StatelessWidget {
  const SystemPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: Every(
        period: const Duration(seconds: 5),
        enabled: vm.polling,
        onTick: vm.onPoll,
        child: SystemScreen(
          vm: vm.screen,
          onTab: vm.onTab,
          onTile: vm.onTile,
          onAttention: vm.onAttention,
          onMeasure: vm.onMeasure,
          onTrafficWindow: (start, end) => vm.onTrafficWindow((start, end)),
          onTrafficFollow: vm.onTrafficFollow,
          onTrafficReset: vm.onTrafficReset,
          onBanner: vm.onBanner,
          onGuide: vm.onGuide,
          onSource: vm.onSource,
          onLevel: vm.onLevel,
          onFilter: vm.onFilter,
          onLines: vm.onLines,
          onAround: vm.onAround,
          onAuto: vm.onAuto,
          onGetLog: vm.onGetLog,
          onCopyLog: vm.onCopyLog,
          onSaveLog: vm.onSaveLog,
          onLogLevel: vm.onLogLevel,
          onClear: vm.onClear,
          onPutProfile: () => unawaited(putProfile(context)),
          onRemoveProfile: vm.onRemoveProfile,
          onCopyCommand: vm.onCopyCommand,
          onBrokerUpdate: () => unawaited(
            showBrokerUpdateDialog(context, follow: vm.updateRuns),
          ),
          onBackUp: () => unawaited(showBackupDialog(context)),
          onRestore: () => unawaited(showBackupDialog(context, restore: true)),
          onOpenBackup: (id) => unawaited(showBackupDialog(context, job: id)),
          onReadBackups: vm.onReadBackups,
          onElsewhere: vm.onElsewhere,
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SystemPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _vm(
    status: sysStatus,
    measure: system.measure,
    attention: attention,
  );

  /// The view-model from the decoded `sys` [status], the traffic [measure]
  /// and the [attention] cards; `sysConfigReason` says why `sys` is locked.
  _Vm _vm({
    required SysStatus status,
    required TrafficMeasure measure,
    required List<AttentionItem> attention,
  }) => _Vm(
    screen: SystemScreenVm(
      site: site.viewed ?? '',
      connected: site.connected,
      broker: status.broker,
      tab: system.tab.sys,
      standby: standby.sys,
      readings: status.readings(unit: sysUnit, about: sysAbout),
      linksTotal: status[SysValue.linksTotal],
      failedLink: failedLinks.firstOrNull?.id,
      waitingLink: oldestWaitingLink?.cn,
      upstreamPeer: connectedPeer(PeerKind.upstream),
      downstreamPeer: connectedPeer(PeerKind.downstream),
      historySize: status[SysValue.historySize],
      traffic: SysTrafficData(
        measure: measure.sys,
        inKey: measure.inward.key,
        outKey: measure.outward.key,
        inNow: status[measure.inward],
        outNow: status[measure.outward],
        unit: sysUnit(measure.inward),
        samples: sysRatesOf(system.samples, measure),
        window: trafficTrend?.sys,
      ),
      log: SysLogData(
        reason: sysConfigReason?.disabled,
        lines: [for (final l in shownLog) l.sys],
        held: system.log.length,
        around: system.around,
        error: system.logError?.sys,
        reading: waiting.systemLog,
        sources: [for (final l in logSourceLinks) l.id],
        source: system.source,
        level: system.logLevel?.sys ?? SysLevel.info,
        filter: system.filter,
        count: system.lines,
        auto: system.auto,
        brokerLevel: shownLogLevel.sys,
      ),
      maintenance: SysMaintData(
        reason: sysConfigReason?.disabled,
        busy: waiting.systemActing,
        stale: [for (final l in clearableLinks) l.stale],
        profiles: [
          for (final p in system.profiles) SysProfile(p.name, points: p.points),
        ],
        profilesUnlisted: system.profilesNote?.said,
        backups: state.backups.card(backupRows),
        version: offeredSelfUpdate?.card,
        dataSize: status[SysValue.dataSize],
      ),
      attention: [for (final a in attention) a.sys],
    ),
    updateRuns: selfUpdate.state.runs,
    polling: systemLogPolls,
    onShow: () => dispatch(ShowSystemAction()),
    onHide: () => dispatch(HideSystemAction()),
    onPoll: () => dispatch(PollSystemLogAction()),
    onTab: (t) => dispatch(OpenSystemTabAction(t.domain)),
    onTile: (t) {
      if (t.place case final p?) {
        dispatchSync(GoSystemPlaceAction(p));
      }
    },
    onAttention: (i) => dispatch(OpenAttentionAction(attention[i])),
    onMeasure: (m) => dispatch(SetMeasureAction(m.domain)),
    onTrafficWindow: (w) => dispatch(ZoomTrafficAction(w.$1, w.$2)),
    onTrafficFollow: () => dispatch(FollowTrafficAction()),
    onTrafficReset: () => dispatch(SetTrafficWindowAction(null)),
    onBanner: () => dispatch(GoSystemPlaceAction(SystemPlace.audit)),
    onGuide: (url) =>
        dispatch(CopyTextAction(url, SystemNotice.guideCopied(url))),
    onSource: (s) => dispatch(ChangeLogQueryAction(SetSourceAction(s))),
    onLevel: (l) => dispatch(ChangeLogQueryAction(SetLogLevelAction(l.domain))),
    onFilter: (f) => dispatch(ChangeLogQueryAction(SetFilterAction(f))),
    // No read: `get_log` takes no time, the filter is over the lines held.
    onAround: (t) => dispatch(SetAroundAction(t)),
    onLines: (n) => dispatch(ChangeLogQueryAction(SetLinesAction(n))),
    onAuto: (on) => dispatch(ChangeLogQueryAction(SetAutoAction(on), read: on)),
    onGetLog: () => dispatch(RetrieveSystemLogAction()),
    onCopyLog: () => dispatch(CopyLogAction()),
    onSaveLog: () => dispatch(SaveLogAction()),
    onLogLevel: (l) => dispatch(StageLogLevelAction(l.domain)),
    onClear: () => dispatch(ClearConnsAction()),
    onRemoveProfile: (name) => dispatch(RemoveProfileAction(name)),
    onCopyCommand: (code) =>
        dispatch(CopyTextAction(code, const SystemNotice.commandCopied())),
    onElsewhere: (e) => dispatch(GoSystemPlaceAction(e.place)),
    onReadBackups: () => dispatch(RetrieveBackupsAction()),
  );
}

/// What System draws ([screen], [updateRuns] and [polling], compared) and
/// what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.screen,
    required this.updateRuns,
    required this.polling,
    required this.onShow,
    required this.onHide,
    required this.onPoll,
    required this.onReadBackups,
    required this.onTab,
    required this.onTile,
    required this.onAttention,
    required this.onMeasure,
    required this.onTrafficWindow,
    required this.onTrafficFollow,
    required this.onTrafficReset,
    required this.onBanner,
    required this.onGuide,
    required this.onSource,
    required this.onLevel,
    required this.onFilter,
    required this.onAround,
    required this.onLines,
    required this.onAuto,
    required this.onGetLog,
    required this.onCopyLog,
    required this.onSaveLog,
    required this.onLogLevel,
    required this.onClear,
    required this.onRemoveProfile,
    required this.onCopyCommand,
    required this.onElsewhere,
  }) : super(equals: [screen, updateRuns, polling]);

  final SystemScreenVm screen;

  /// The broker says an update of itself runs or ended.
  final bool updateRuns;

  /// The Log tab reads again every 5 s.
  final bool polling;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onPoll;
  final ValueChanged<SysTab> onTab;
  final ValueChanged<SysTileKey> onTile;
  final ValueChanged<int> onAttention;
  final ValueChanged<SysMeasure> onMeasure;

  /// The traffic trend's window, its start and end (µs).
  final ValueChanged<(int, int)> onTrafficWindow;
  final VoidCallback onTrafficFollow;
  final VoidCallback onTrafficReset;
  final VoidCallback onBanner;
  final ValueChanged<String> onGuide;
  final ValueChanged<String?> onSource;
  final ValueChanged<SysLevel> onLevel;
  final ValueChanged<String?> onFilter;
  final ValueChanged<String?> onAround;
  final ValueChanged<int> onLines;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGetLog;
  final VoidCallback onCopyLog;
  final VoidCallback onSaveLog;
  final ValueChanged<SysLevel> onLogLevel;
  final VoidCallback onClear;
  final ValueChanged<String> onRemoveProfile;
  final ValueChanged<String> onCopyCommand;
  final ValueChanged<SysElsewhere> onElsewhere;
  final VoidCallback onReadBackups;
}
