import 'dart:async';
import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/access/actions/set_tab_action.dart'
    as access_slice;
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/add_changes_action.dart';
import 'package:business/redux/changes/actions/remove_change_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/set_selected_link_action.dart';
import 'package:business/redux/links/actions/set_tab_action.dart'
    as links_slice;
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/peers/actions/retrieve_peers_action.dart';
import 'package:business/redux/peers/actions/set_selected_peer_action.dart';
import 'package:business/redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/set_selected_entry_action.dart';
import 'package:business/redux/system/actions/clear_conns_action.dart';
import 'package:business/redux/system/actions/poll_system_log_action.dart';
import 'package:business/redux/system/actions/remove_profile_action.dart';
import 'package:business/redux/system/actions/retrieve_profiles_action.dart';
import 'package:business/redux/system/actions/retrieve_sys_about_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/redux/system/actions/set_acl_seen_action.dart';
import 'package:business/redux/system/actions/set_auto_action.dart';
import 'package:business/redux/system/actions/set_filter_action.dart';
import 'package:business/redux/system/actions/set_lines_action.dart';
import 'package:business/redux/system/actions/set_log_level_action.dart';
import 'package:business/redux/system/actions/set_measure_action.dart';
import 'package:business/redux/system/actions/set_shown_action.dart';
import 'package:business/redux/system/actions/set_source_action.dart';
import 'package:business/redux/system/actions/set_tab_action.dart';
import 'package:business/wyrm/mappers/log_line_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:models/attention_kind.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/links_tab.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/staged_change.dart';
import 'package:models/standby_state.dart';
import 'package:models/traffic_sample.dart';
import 'package:models/workspace.dart';
import 'package:ui/alerts/styled_snackbar.dart';
import 'package:ui/alerts/warn_banner.dart';
import 'package:ui/buttons/pill_tabs.dart';
import 'package:ui/charts/traffic_card.dart';
import 'package:ui/containers/attention_panel.dart';
import 'package:ui/containers/command_card.dart';
import 'package:ui/containers/guide_card.dart';
import 'package:ui/containers/standby_pair.dart';
import 'package:ui/containers/sys_tile.dart';
import 'package:ui/forms/log_toolbar.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/pages/system_page.dart';
import 'package:ui/tables/log_table.dart';
import 'package:ui/tables/row_list.dart';
import 'package:ui/tables/term_table.dart';

import '../common/every.dart';
import '../common/tab_visibility.dart';
import '../dialogs/profile_dialog.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// The levels of `sys/log_level`, by enum code.
const _logLevels = ['error', 'warn', 'info', 'debug', 'trace'];

/// The order of the Log toolbar's level list (board `SystemLog`).
const _toolbarLevels = ['info', 'warn', 'error', 'debug', 'trace'];

/// The warm standby section of the operations guide.
const _guideUrl =
    'https://github.com/gencto/wyrm/blob/main/docs/operations.md'
    '#warm-standby-adr-0036-option-3-stage-a';

/// Where the commands of Maintenance point when Studio does not know the
/// host's own paths (the broker serves neither).
const _dataDir = '/var/lib/wyrm';
const _configPath = '/etc/wyrm/wyrmd.json5';

/// `arbiter_lease_s` at or below this is "renewing late" (proposed).
const _leaseLate = 3;

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
        child: SystemPage(
          title: S.current.wyrmdOn(vm.site),
          pill: vm.pill,
          meta: vm.meta,
          stale: vm.stale,
          tabsLabel: S.current.sysTabsLabel,
          tabs: vm.tabs,
          tab: vm.tab,
          onTab: vm.onTab,
          overview: vm.overview,
          availability: vm.availability,
          log: vm.log,
          maintenance: vm.maintenance,
          attention: vm.attention,
          onAttention: (id) => vm.onAttention(context, id),
          onTile: (key) => vm.onTile(context, key),
          onMeasure: vm.onMeasure,
          onBanner: () => vm.onElsewhere(context, 'audit'),
          onGuide: () => vm.onGuide(context),
          onSource: vm.onSource,
          onLevel: vm.onLevel,
          onFilter: vm.onFilter,
          onLines: vm.onLines,
          onAuto: vm.onAuto,
          onGetLog: vm.onGetLog,
          onCopyLog: () => vm.onCopyLog(context),
          onSaveLog: () => vm.onSaveLog(context),
          onLogLevel: vm.onLogLevel,
          onClear: () => vm.onClear(context),
          onPutProfile: () => vm.onPutProfile(context),
          onRemoveProfile: (name) => vm.onRemoveProfile(context, name),
          onCopyCommand: (id) => vm.onCopyCommand(context, id),
          onElsewhere: (id) => vm.onElsewhere(context, id),
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SystemPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _sys => '${site.root}/sys';

  List<String> get _watch => [
    '$_sys/*',
    '$_sys/links/*/state',
    '$_sys/history/database_size',
  ];

  double? _n(String k) => switch (live.values['$_sys/$k']?.value) {
    final num n => n.toDouble(),
    _ => null,
  };

  String? _s(String k) => switch (live.values['$_sys/$k']?.value) {
    null => null,
    final Object o => '$o',
  };

  String _about(String k) => system.about['$_sys/$k'] ?? '';

  /// The node's own unit (specs/system.md, Data), else [fallback].
  String _unit(String k, String fallback) =>
      system.units['$_sys/$k'] ?? fallback;

  /// `sys/log_level` as a name (the value is an enum code).
  String? get _brokerLevel => switch (live.values['$_sys/log_level']?.value) {
    final int i when i >= 0 && i < _logLevels.length => _logLevels[i],
    final double d when d >= 0 && d < _logLevels.length =>
      _logLevels[d.toInt()],
    final String s => s,
    _ => null,
  };

  StagedChange? get _stagedLevel => changes.table.values
      .where((c) => c.key == '$_sys/log_level' && c.field == 'value')
      .firstOrNull;

  @override
  _Vm fromStore() {
    final reason = site.needs('config', _sys);
    final lag = _n('standby_lag') ?? 0;
    final forks = _n('standby_forks') ?? 0;
    final failed = failedLinks;
    final waitingLinks = [
      for (final id in quarantine.view)
        if (quarantine.table[id] case final q?
            when !q.deauthorized && q.kind != 'broker')
          q,
    ];
    final acl = _n('acl_denied');
    final staged = _stagedLevel;
    final level = staged?.to ?? _brokerLevel ?? 'info';
    final connected = site.connected;
    return _Vm(
      site: site.viewed ?? '',
      pill: StatusPillVm(
        label: connected
            ? S.current.sysRunningActive
            : S.current.sysUnreachable,
        tone: connected ? Tone.good : Tone.bad,
      ),
      stale: !connected,
      meta: _meta(),
      tab: system.tab,
      tabs: [
        PillTabVm(id: SystemPage.overviewTab, label: S.current.sysTabOverview),
        PillTabVm(
          id: SystemPage.availabilityTab,
          label: S.current.sysTabAvailability,
          dot: switch (standby) {
            StandbyState.unknown => null,
            final s => availabilityDot(
              standby: s != StandbyState.none,
              behind: s == StandbyState.behind,
            ),
          },
        ),
        PillTabVm(id: SystemPage.logTab, label: S.current.sysTabLog),
        PillTabVm(
          id: SystemPage.maintenanceTab,
          label: S.current.sysTabMaintenance,
        ),
      ],
      overview: _overview(failed, waitingLinks),
      availability: _availability(lag, forks),
      log: _log(reason, level),
      maintenance: _maintenance(reason),
      attention: _attention(),
      polling: system.auto && system.tab == SystemPage.logTab && reason == null,
      onShow: () {
        dispatchSync(SetShownAction(true));
        dispatchSync(WatchKeysAction(_watch));
        unawaited(_load());
      },
      onHide: () {
        dispatchSync(SetShownAction(false));
        dispatchSync(UnwatchKeysAction(_watch));
        // What the ACL counter was when the screen was left: the attention
        // panel says so when it has grown by the next visit.
        if (acl != null) {
          dispatchSync(SetAclSeenAction(acl.toInt()));
        }
      },
      onPoll: () => unawaited(dispatchAndWait(PollSystemLogAction())),
      onTab: (t) {
        dispatchSync(SetTabAction(t));
        if (t == SystemPage.logTab) {
          _readLog();
        }
      },
      onMeasure: (m) => dispatchSync(SetMeasureAction(m)),
      onSource: (s) {
        dispatchSync(SetSourceAction(s.isEmpty ? null : s));
        _readLog();
      },
      onLevel: (l) {
        dispatchSync(SetLogLevelAction(l));
        _readLog();
      },
      onFilter: (f) {
        dispatchSync(SetFilterAction(f.isEmpty ? null : f));
        _readLog();
      },
      onLines: (n) {
        dispatchSync(SetLinesAction(n));
        _readLog();
      },
      onAuto: (on) {
        dispatchSync(SetAutoAction(on));
        if (on) {
          _readLog();
        }
      },
      onGetLog: _readLog,
      onCopyLog: _copyLog,
      onSaveLog: _saveLog,
      onLogLevel: _stageLevel,
      onClear: _clear,
      onPutProfile: (context) async {
        final name = await putProfile(context);
        if (name != null && context.mounted) {
          _say(context, S.current.sysProfilePut(name));
        }
      },
      onRemoveProfile: _removeProfile,
      onCopyCommand: (context, id) {
        final command = _commands()
            .where((c) => c.id == id)
            .map((c) => c.code)
            .firstOrNull;
        if (command != null) {
          unawaited(Clipboard.setData(ClipboardData(text: command)));
          _say(context, S.current.sysCommandCopied);
        }
      },
      onTile: _openTile,
      onAttention: _openAttention,
      onElsewhere: _openElsewhere,
      onGuide: (context) {
        unawaited(Clipboard.setData(const ClipboardData(text: _guideUrl)));
        _say(context, S.current.sysGuideCopied(_guideUrl));
      },
    );
  }

  // ---- reads ---------------------------------------------------------------

  Future<void> _load() async {
    unawaited(dispatchAndWait(RetrieveSysAboutAction()));
    unawaited(dispatchAndWait(RetrieveProfilesAction()));
    unawaited(dispatchAndWait(RetrieveQuarantineAction()));
    if (state.system.tab == SystemPage.logTab) {
      _readLog();
    }
    await dispatchAndWait(RetrieveLinksAction(quiet: true));
    if (state.peers.table.isEmpty) {
      await dispatchAndWait(RetrievePeersAction());
    }
  }

  void _readLog() {
    if (site.needs('config', _sys) == null) {
      unawaited(dispatchAndWait(RetrieveSystemLogAction()));
    }
  }

  // ---- the title row -------------------------------------------------------

  String _meta() {
    final parts = [
      ?_s('version'),
      if (_s('zenoh_version') case final z?) 'Zenoh $z',
      ?_s('distribution'),
      if (_s('start_time') case final t?) S.current.sysMetaStarted(_utc(t)),
      if (_n('uptime') case final u?) S.current.upFor(_duration(u)),
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  // ---- Overview ------------------------------------------------------------

  SystemOverviewVm _overview(
    List<LinkInfo> failed,
    List<QuarantineEntry> waitingLinks,
  ) {
    final quarantined = _n('quarantined') ?? 0;
    final oldest = [...waitingLinks]
      ..sort(
        (a, b) => (a.firstSeen ?? DateTime(0)).compareTo(
          b.firstSeen ?? DateTime(0),
        ),
      );
    String? peer(PeerKind kind) => peers.table.values
        .where((p) => p.kind == kind && p.connected)
        .map((p) => p.site)
        .firstOrNull;
    final up = (_n('upstream_connected') ?? 0) > 0
        ? peer(PeerKind.upstream)
        : null;
    final down = (_n('downstream_connected') ?? 0) > 0
        ? peer(PeerKind.downstream)
        : null;
    final (memory, memoryUnit) = _size(_n('memory'));
    final (disk, diskUnit) = _size(_n('disk_free'));
    final (data, dataUnit) = _size(_n('data_size'));
    final history = switch (live.values['$_sys/history/database_size']?.value) {
      final num n => n.toDouble(),
      _ => null,
    };
    return SystemOverviewVm(
      groups: [
        TileGroupVm(
          label: S.current.sysGroupLinks,
          tiles: [
            SysTileVm(
              label: S.current.mLinksConnected,
              keyName: 'links_connected',
              value: _count(_n('links_connected')),
              unit: switch (_n('links_total')) {
                final t? => S.current.sysOfTotal(_count(t)),
                null => '',
              },
              sub: failed.isEmpty
                  ? S.current.sysSubOpenLinks
                  : S.current.sysSubLinkFailed(failed.first.id),
              subTone: failed.isEmpty ? Tone.neutral : Tone.bad,
              about: _about('links_connected'),
              link: true,
            ),
            SysTileVm(
              label: S.current.mInQuarantine,
              keyName: 'quarantined',
              value: _count(_n('quarantined')),
              sub: oldest.isEmpty
                  ? S.current.sysSubOpenQuarantine
                  : S.current.sysSubWaits(_name(oldest.first.cn)),
              tone: quarantined > 0 ? Tone.warn : Tone.neutral,
              subTone: quarantined > 0 ? Tone.warn : Tone.neutral,
              outlined: quarantined > 0,
              about: _about('quarantined'),
              link: true,
            ),
            SysTileVm(
              label: S.current.sysPackages,
              keyName: 'packages_total',
              value: _count(_n('packages_total')),
              sub: S.current.sysSubPackages,
              about: _about('packages_total'),
              link: true,
            ),
            SysTileVm(
              label: S.current.sysUpstream,
              keyName: 'upstream_connected',
              value: _count(_n('upstream_connected')),
              unit: S.current.sysUnitConnected,
              sub: up == null
                  ? S.current.sysSubOpenSites
                  : S.current.sysSubPeer(up),
              about: _about('upstream_connected'),
              link: true,
            ),
            SysTileVm(
              label: S.current.sysDownstream,
              keyName: 'downstream_connected',
              value: _count(_n('downstream_connected')),
              unit: S.current.sysUnitConnected,
              sub: down == null
                  ? S.current.sysSubOpenSites
                  : S.current.sysSubPeer(down),
              about: _about('downstream_connected'),
              link: true,
            ),
            SysTileVm(
              label: S.current.mSessions,
              keyName: 'sessions',
              value: _count(_n('sessions')),
              sub: S.current.sysSubSessions,
              about: _about('sessions'),
            ),
          ],
        ),
        TileGroupVm(
          label: S.current.sysGroupProcess,
          tiles: [
            SysTileVm(
              label: 'CPU',
              keyName: 'cpu',
              value: _figure(_n('cpu')),
              unit: _unit('cpu', '%'),
              sub: S.current.sysSubCpu,
              about: _about('cpu'),
            ),
            SysTileVm(
              label: S.current.mMemory,
              keyName: 'memory',
              value: memory,
              unit: memoryUnit,
              sub: S.current.sysSubMemory,
              about: _about('memory'),
            ),
            SysTileVm(
              label: S.current.mFreeDisk,
              keyName: 'disk_free',
              value: disk,
              unit: diskUnit,
              sub: S.current.sysSubDisk,
              about: _about('disk_free'),
            ),
            SysTileVm(
              label: 'data_dir',
              keyName: 'data_size',
              value: data,
              unit: dataUnit,
              sub: history == null
                  ? S.current.sysSubOpenHistory
                  : S.current.sysSubData(_sizeText(history)),
              about: _about('data_size'),
              link: true,
            ),
            SysTileVm(
              label: S.current.mAclDenials,
              keyName: 'acl_denied',
              value: _count(_n('acl_denied')),
              sub: S.current.sysSubAcl,
              about: _about('acl_denied'),
              link: true,
            ),
            SysTileVm(
              label: S.current.mAuditRecords,
              keyName: 'audit_records',
              value: _count(_n('audit_records')),
              sub: S.current.sysSubAudit,
              about: _about('audit_records'),
              link: true,
            ),
          ],
        ),
      ],
      traffic: _traffic(),
    );
  }

  TrafficCardVm _traffic() {
    final measure = system.measure;
    final (key, unit, scale) = switch (measure) {
      'frames' => (
        'frames',
        _unit('frames_in_per_second', 'frame/s'),
        1.0,
      ),
      // The broker serves bytes per second; the board shows kB/s.
      'bytes' => ('data', 'kB/s', 0.001),
      _ => ('messages', _unit('messages_in_per_second', 'msg/s'), 1.0),
    };
    double of(TrafficSample s, {required bool inward}) =>
        scale *
        switch (measure) {
          'frames' => inward ? s.framesIn : s.framesOut,
          'bytes' => inward ? s.dataIn : s.dataOut,
          _ => inward ? s.messagesIn : s.messagesOut,
        };
    String now(String k) => switch (_n(k)) {
      final v? => _figure(v * scale),
      null => '—',
    };
    final samples = system.samples;
    final label = switch (measure) {
      'frames' => S.current.sysFrames,
      'bytes' => S.current.sysBytes,
      _ => S.current.sysMessages,
    };
    return TrafficCardVm(
      title: S.current.sysTraffic,
      measures: [
        PillTabVm(id: 'messages', label: S.current.sysMessages),
        PillTabVm(id: 'frames', label: S.current.sysFrames),
        PillTabVm(id: 'bytes', label: S.current.sysBytes),
      ],
      measure: measure,
      inLabel: S.current.sysIn,
      outLabel: S.current.sysOut,
      inKey: '${key}_in_per_second',
      outKey: '${key}_out_per_second',
      inNow: now('${key}_in_per_second'),
      outNow: now('${key}_out_per_second'),
      unit: unit,
      inSeries: [for (final s in samples) of(s, inward: true)],
      outSeries: [for (final s in samples) of(s, inward: false)],
      axis: samples.length < 2
          ? const []
          : [
              _clock(samples.first.time),
              S.current.sysNow(_clock(samples.last.time)),
            ],
      note: S.current.sysTrafficNote,
      empty: S.current.sysCollecting,
      describe: samples.length < 2
          ? ''
          : S.current.sysTrafficDescribe(
              label,
              _clock(samples.first.time),
              _clock(samples.last.time),
            ),
    );
  }

  // ---- Availability --------------------------------------------------------

  SystemAvailVm _availability(double lag, double forks) {
    final name = site.viewed ?? '';
    if (standby == StandbyState.unknown || standby == StandbyState.none) {
      return SystemAvailVm(
        guide: GuideCardVm(
          title: S.current.sysNoStandbyTitle,
          body: S.current.sysNoStandbyBody,
          stepsTitle: S.current.sysNoStandbySteps,
          steps: [
            S.current.sysNoStandbyStep1,
            S.current.sysNoStandbyStep2(
              'standby: {peer, takeover_s, primary, witness}',
            ),
            S.current.sysNoStandbyStep3,
          ],
          link: S.current.sysGuideLink,
        ),
      );
    }
    final behind = standby == StandbyState.behind;
    final lease = _n('arbiter_lease_s') ?? 0;
    final late = lease > 0 && lease <= _leaseLate;
    return SystemAvailVm(
      pair: StandbyPairVm(
        activeLabel: S.current.sysThisActive,
        activeName: name,
        activeNote: S.current.sysActiveNote,
        flow: S.current.sysFlow,
        every: S.current.sysPulled,
        standbyLabel: behind
            ? S.current.sysStandbyBehind
            : S.current.sysStandbyFollowing,
        standbyName: 'standby:$name',
        standbyNote: S.current.sysStandbyNote,
        behind: behind,
      ),
      tiles: [
        SysTileVm(
          label: S.current.sysStandbyConnected,
          keyName: 'standby_connected',
          value: _count(_n('standby_connected')),
          sub: S.current.sysSubFollows,
          tone: Tone.good,
          about: _about('standby_connected'),
        ),
        SysTileVm(
          label: S.current.sysLag,
          keyName: 'standby_lag',
          value: _count(lag),
          unit: S.current.sysRecords,
          sub: lag > 0 ? S.current.sysSubLag : S.current.sysSubLagNone,
          tone: lag > 0 ? Tone.warn : Tone.neutral,
          subTone: lag > 0 ? Tone.warn : Tone.neutral,
          outlined: lag > 0,
          about: _about('standby_lag'),
        ),
        SysTileVm(
          label: S.current.sysArbiterLease,
          keyName: 'arbiter_lease_s',
          value: lease > 0 ? _count(lease) : '—',
          unit: lease > 0 ? S.current.sysSecondsLeft : '',
          sub: lease <= 0
              ? S.current.sysSubNoArbiter
              : (late ? S.current.sysSubLeaseLate : S.current.sysSubLease),
          tone: late ? Tone.warn : Tone.neutral,
          subTone: late ? Tone.warn : Tone.neutral,
          about: _about('arbiter_lease_s'),
        ),
        SysTileVm(
          label: S.current.sysForks,
          keyName: 'standby_forks',
          value: _count(forks),
          unit: S.current.sysSinceStart,
          sub: forks > 0 ? S.current.sysSubForks : S.current.sysSubForksNone,
          tone: forks > 0 ? Tone.bad : Tone.neutral,
          subTone: forks > 0 ? Tone.bad : Tone.neutral,
          about: _about('standby_forks'),
        ),
      ],
      banner: behind
          ? WarnBannerVm(
              title: lag > 0 && forks > 0
                  ? S.current.sysBannerBoth
                  : (lag > 0
                        ? S.current.sysBannerBehind
                        : S.current.sysBannerFork),
              body: [
                if (lag > 0) S.current.sysBannerLag(_count(lag)),
                if (forks > 0) S.current.sysBannerForks(_count(forks)),
              ].join(' '),
              action: forks > 0 ? S.current.sysOpenAuditRecord : null,
            )
          : null,
      heldTitle: S.current.sysHeld,
      held: [
        TermVm(
          term: S.current.sysHeldControl,
          text: S.current.sysHeldControlNote,
        ),
        TermVm(
          term: S.current.sysHeldSecrets,
          text: S.current.sysHeldSecretsNote,
        ),
        TermVm(
          term: S.current.sysHeldStorage,
          text: S.current.sysHeldStorageNote,
        ),
        TermVm(
          term: S.current.sysHeldHistory,
          text: S.current.sysHeldHistoryNote,
        ),
      ],
    );
  }

  // ---- Log -----------------------------------------------------------------

  SystemLogVm _log(String? reason, String level) {
    final rows = reason == null
        ? [
            for (final l in system.log)
              LogRowVm(
                time: _logTime(l.time),
                level: l.level.toUpperCase(),
                target: l.target,
                message: l.message,
              ),
          ]
        : const <LogRowVm>[];
    final error = reason == null ? system.logError : null;
    return SystemLogVm(
      toolbar: LogToolbarVm(
        sourceLabel: S.current.sysSource,
        sources: [
          ChoiceItemVm(value: '', label: S.current.sysBrokerAll),
          for (final id in links.view)
            if (links.table[id] case final l?
                when l.mode == LinkMode.embedded || l.mode == LinkMode.wasm)
              ChoiceItemVm(value: l.id, label: S.current.sysLinkSource(l.id)),
        ],
        source: system.source ?? '',
        levelLabel: S.current.sysLevelMore,
        levels: [
          for (final l in _toolbarLevels) ChoiceItemVm(value: l, label: l),
        ],
        level: system.logLevel ?? 'info',
        filterLabel: S.current.sysFilter,
        filterHint: S.current.sysFilterHint,
        filter: system.filter ?? '',
        linesLabel: S.current.sysLines,
        lines: system.lines,
        autoLabel: S.current.sysEvery5s,
        auto: system.auto,
        getLabel: S.current.sysGetLog,
        disabledReason: reason,
      ),
      summary: reason == null
          ? S.current.sysLogSummary(rows.length)
          : S.current.sysLogSummaryNone,
      copyLabel: S.current.sysCopy,
      saveLabel: S.current.sysSaveLog,
      rows: rows,
      message:
          error ??
          (reason == null
              ? (system.isWaiting ? '…' : S.current.sysNoLines)
              : S.current.sysLogNeedsConfig),
      bad: error != null,
      levelTitle: S.current.sysBrokerLogLevel,
      levelKey: 'sys/log_level',
      levelNote: S.current.sysLogLevelNote,
      levels: [for (final l in _logLevels) PillTabVm(id: l, label: l)],
      level: level,
      levelReason: reason,
    );
  }

  /// Picking a level stages `sys/log_level` (an enum: its index is
  /// written, its name shown); picking the broker's own level again takes
  /// the staged change back.
  void _stageLevel(String level) {
    final current = _brokerLevel;
    final staged = _stagedLevel;
    if (level == current) {
      if (staged != null) {
        dispatchSync(RemoveChangeAction(staged.id));
      }
      return;
    }
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            id: 'set:$_sys/log_level',
            op: 'Edit',
            key: '$_sys/log_level',
            field: 'value',
            from: current ?? '—',
            to: level,
            level: 'config',
            value: _logLevels.indexOf(level),
          ),
        ].lock,
      ),
    );
  }

  void _copyLog(BuildContext context) {
    final lines = system.log;
    if (lines.isEmpty) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: logText(lines))));
    _say(context, S.current.sysLogCopied(lines.length));
  }

  Future<void> _saveLog(BuildContext context) async {
    final lines = system.log;
    if (lines.isEmpty) {
      return;
    }
    final text = '${logText(lines)}\n';
    try {
      final path = await FilePicker.saveFile(
        fileName: logFileName(site.viewed ?? 'site', DateTime.now()),
        type: FileType.custom,
        allowedExtensions: const ['log'],
      );
      if (path == null) {
        return;
      }
      await File(path).writeAsString(text);
      if (context.mounted) {
        _say(context, S.current.sysLogSaved(path));
      }
    } on Object catch (e) {
      if (context.mounted) {
        _say(context, '$e', title: S.current.sysLogNotSaved);
      }
    }
  }

  // ---- Maintenance ---------------------------------------------------------

  List<CommandCardVm> _commands() {
    final slash = _dataDir.lastIndexOf('/');
    final parent = _dataDir.substring(0, slash);
    final dir = _dataDir.substring(slash + 1);
    final name = site.viewed ?? 'site';
    return [
      CommandCardVm(
        id: 'backup',
        title: S.current.sysCmdBackup,
        code:
            'sudo systemctl stop wyrmd\n'
            'sudo tar --same-permissions -czf /backup/wyrm-$name.tgz '
            '-C $parent $dir\n'
            'sudo systemctl start wyrmd',
        note: S.current.sysCmdBackupNote,
        copyLabel: S.current.sysCopyCommand(S.current.sysCmdBackup),
      ),
      CommandCardVm(
        id: 'verify',
        title: S.current.sysCmdVerify,
        code: 'wyrmd -c $_configPath verify',
        note: S.current.sysCmdVerifyNote,
        copyLabel: S.current.sysCopyCommand(S.current.sysCmdVerify),
      ),
      CommandCardVm(
        id: 'check',
        title: S.current.sysCmdCheck,
        code: 'wyrmd -c $_configPath check',
        note: S.current.sysCmdCheckNote,
        copyLabel: S.current.sysCopyCommand(S.current.sysCmdCheck),
      ),
    ];
  }

  SystemMaintVm _maintenance(String? reason) {
    final stale = clearableLinks;
    final busy = system.isActing ? '…' : null;
    final data = _n('data_size');
    final unlisted = system.profilesNote;
    return SystemMaintVm(
      staleTitle: S.current.sysStale,
      staleNote: S.current.sysStaleNote,
      stale: [
        for (final l in stale)
          RowItemVm(
            id: l.id,
            title: l.id,
            subtitle: S.current.sysStaleRow(l.certificateCn ?? 'link:${l.id}'),
            trailing: S.current.sysNotConnected,
          ),
      ],
      staleEmpty: S.current.sysNoStale,
      clearLabel: switch (stale.length) {
        0 => S.current.sysClearNone,
        1 => S.current.sysClearOne,
        final n => S.current.sysClearBoard(n),
      },
      clearReason:
          reason ??
          busy ??
          (stale.isEmpty ? S.current.sysNothingToClear : null),
      staleFooter: S.current.sysClearFooter,
      profilesTitle: S.current.sysProfiles,
      profilesNote: S.current.sysProfilesNote,
      putLabel: S.current.sysPutProfile,
      putReason: reason ?? busy,
      profiles: [
        for (final p in system.profiles)
          RowItemVm(
            id: p.name,
            title: p.name,
            trailing: switch (p.points) {
              final n? => S.current.pointsCount(n),
              null => '',
            },
            action: S.current.sysRemove,
            actionHint: S.current.sysRemoveProfile(p.name),
            actionReason: reason ?? busy,
          ),
      ],
      profilesEmpty: unlisted == null
          ? S.current.sysNoProfiles
          : S.current.sysProfilesUnlisted(unlisted),
      profilesUnlisted: unlisted != null,
      profilesFooter: S.current.sysProfilesFooter,
      backupTitle: S.current.sysBackup,
      backupNote: data == null
          ? S.current.sysBackupNoteNoSize
          : S.current.sysBackupNote(_sizeText(data)),
      commands: _commands(),
      backupWarning: S.current.sysBackupWarning,
      elsewhereLabel: S.current.sysElsewhere,
      elsewhere: [
        ElsewhereVm(id: 'quarantine', label: S.current.sysElsewhereLinks),
        ElsewhereVm(id: 'sites', label: S.current.sysElsewhereSites),
        ElsewhereVm(id: 'access', label: S.current.sysElsewhereAccess),
        ElsewhereVm(id: 'history', label: S.current.sysElsewhereHistory),
        // The gallery of the design system, in development builds only.
        if (kDebugMode)
          ElsewhereVm(id: 'gallery', label: S.current.designGallery),
      ],
    );
  }

  /// `clear_conns` asks first, with the ids it would remove; its answer
  /// (the ids the broker did remove) is a toast.
  Future<void> _clear(BuildContext context) async {
    final ids = [for (final l in clearableLinks) l.id];
    if (ids.isEmpty) {
      return;
    }
    final yes = await ConfirmDialog.ask(
      context,
      title: S.current.sysClearAsk,
      message: S.current.sysClearAskBody(ids.join(', ')),
      confirm: S.current.sysClearConfirm,
      cancel: S.current.cancel,
    );
    if (!yes) {
      return;
    }
    final action = ClearConnsAction();
    final status = await dispatchAndWait(action);
    if (status.isCompletedOk && context.mounted) {
      _say(
        context,
        action.removed.isEmpty
            ? S.current.sysClearedNone
            : S.current.sysCleared(action.removed.join(', ')),
      );
    }
  }

  Future<void> _removeProfile(BuildContext context, String name) async {
    final yes = await ConfirmDialog.ask(
      context,
      title: S.current.sysRemoveProfile(name),
      message: S.current.sysRemoveProfileAsk(name),
      confirm: S.current.sysRemove,
      cancel: S.current.cancel,
    );
    if (!yes) {
      return;
    }
    final status = await dispatchAndWait(RemoveProfileAction(name));
    if (status.isCompletedOk && context.mounted) {
      _say(context, S.current.sysProfileRemoved(name));
    }
  }

  // ---- the attention panel -------------------------------------------------

  AttentionPanelVm _attention() {
    final items = [
      for (final a in attention)
        switch (a.kind) {
          AttentionKind.standbyBehind => AttentionItemVm(
            id: 'standby',
            title: a.count > 0
                ? S.current.sysAttnBehind(_count(a.count.toDouble()))
                : S.current.sysAttnFork,
            detail: a.more > 0
                ? S.current.sysAttnBehindDetail(a.more)
                : S.current.sysAttnBehindPlain,
            go: S.current.sysAttnOpenAvail,
          ),
          AttentionKind.linkFailed => AttentionItemVm(
            id: 'link:${a.subject}',
            title: S.current.sysAttnLinkFailed(a.subject),
            detail: S.current.sysAttnLinkDetail(a.subject),
            go: S.current.sysAttnOpenLinks,
            tone: Tone.bad,
          ),
          AttentionKind.quarantine => AttentionItemVm(
            id: 'quarantine:${a.subject}',
            title: S.current.sysAttnQuarantine(_name(a.name)),
            detail: switch (a.since) {
              final t? => S.current.sysAttnQuarantineSince(a.name, _clock(t)),
              null => S.current.sysAttnQuarantineDetail(a.name),
            },
            go: S.current.sysAttnOpenQuarantine,
          ),
          AttentionKind.brokerWaiting => AttentionItemVm(
            id: 'broker:${a.subject}',
            title: S.current.sysAttnBroker(_name(a.name)),
            detail: a.count == 0
                ? S.current.sysAttnBrokerPlain
                : S.current.sysAttnBrokerRelays(a.count),
            go: S.current.sysAttnOpenSites,
          ),
          AttentionKind.aclGrown => AttentionItemVm(
            id: 'acl',
            title: S.current.sysAttnAcl(_count(a.count.toDouble())),
            detail: S.current.sysAttnAclDetail(_count(a.more.toDouble())),
            go: S.current.sysAttnOpenAudit,
          ),
          AttentionKind.noStandby => AttentionItemVm(
            id: 'no-standby',
            title: S.current.sysAttnNoStandby,
            detail: S.current.sysAttnNoStandbyDetail,
            go: S.current.sysAttnOpenAvail,
            tone: Tone.neutral,
          ),
        },
    ];
    final name = site.viewed ?? '';
    return AttentionPanelVm(
      heading: S.current.sysNeedsLook(items.length),
      note: S.current.sysNeedsLookNote,
      empty: S.current.sysNothing,
      items: items,
      factsTitle: S.current.sysThisBroker,
      facts: [
        BrokerFactVm(label: S.current.sysFactSite, value: name, mono: true),
        BrokerFactVm(
          label: S.current.sysFactLiveliness,
          value: 'wy/$name/sys/broker',
          mono: true,
          dot: site.connected ? Tone.good : Tone.bad,
        ),
        BrokerFactVm(
          label: S.current.factStarted,
          value: switch (_s('start_time')) {
            final t? => _utc(t),
            null => '—',
          },
        ),
        BrokerFactVm(
          label: S.current.factBuild,
          value: switch ([?_s('version'), ?_s('distribution')]) {
            [] => '—',
            final parts => parts.join(' · '),
          },
        ),
      ],
    );
  }

  // ---- where things lead ---------------------------------------------------

  static void _go(BuildContext context, Workspace ws) =>
      AutoTabsRouter.of(context).setActiveIndex(ws.index);

  void _openTile(BuildContext context, String key) {
    switch (key) {
      case 'links_connected' || 'packages_total':
        dispatchSync(links_slice.SetTabAction(LinksTab.local));
        _go(context, Workspace.links);
      case 'quarantined':
        _openElsewhere(context, 'quarantine');
      case 'upstream_connected' || 'downstream_connected':
        _go(context, Workspace.sites);
      case 'data_size':
        _go(context, Workspace.history);
      case 'acl_denied' || 'audit_records':
        _openElsewhere(context, 'audit');
    }
  }

  void _openElsewhere(BuildContext context, String id) {
    switch (id) {
      case 'quarantine':
        dispatchSync(links_slice.SetTabAction(LinksTab.quarantine));
        _go(context, Workspace.links);
      case 'sites':
        _go(context, Workspace.sites);
      case 'access':
        _go(context, Workspace.access);
      case 'audit':
        dispatchSync(access_slice.SetTabAction('audit'));
        _go(context, Workspace.access);
      case 'history':
        _go(context, Workspace.history);
      case 'gallery':
        dispatchSync(GoAction.push(const GalleryRoute()));
    }
  }

  void _openAttention(BuildContext context, String id) {
    final colon = id.indexOf(':');
    final kind = colon < 0 ? id : id.substring(0, colon);
    final what = colon < 0 ? '' : id.substring(colon + 1);
    switch (kind) {
      case 'standby' || 'no-standby':
        dispatchSync(SetTabAction(SystemPage.availabilityTab));
      case 'link':
        final external = links.table[what]?.mode == LinkMode.external;
        dispatchSync(
          links_slice.SetTabAction(external ? LinksTab.remote : LinksTab.local),
        );
        dispatchSync(SetSelectedLinkAction(what));
        _go(context, Workspace.links);
      case 'quarantine':
        dispatchSync(links_slice.SetTabAction(LinksTab.quarantine));
        dispatchSync(SetSelectedEntryAction(what));
        _go(context, Workspace.links);
      case 'broker':
        dispatchSync(SetSelectedPeerAction('waiting:$what'));
        _go(context, Workspace.sites);
      case 'acl':
        _openElsewhere(context, 'audit');
    }
  }

  // ---- words ---------------------------------------------------------------

  static void _say(BuildContext context, String message, {String? title}) =>
      StyledSnackbar.instance.show(
        context: context,
        title: title,
        message: message,
        duration: const Duration(seconds: 3),
      );

  /// `link:field-gw` and `broker:line2` as the name alone.
  static String _name(String cn) {
    final colon = cn.indexOf(':');
    return colon < 0 ? cn : cn.substring(colon + 1);
  }

  /// A whole number with thousands separated (`18,402`); `—` for none.
  static String _count(double? n) {
    if (n == null) {
      return '—';
    }
    final digits = n.round().abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// A measured figure: one decimal below 100, none from 100 up.
  static String _figure(double? n) {
    if (n == null) {
      return '—';
    }
    if (n.abs() >= 100) {
      return _count(n);
    }
    final s = n.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// `memory`, `disk_free`, `data_size` are MiB; GiB from 1024 (the only
  /// conversion Studio makes): the figure and its unit.
  static (String, String) _size(double? mib) {
    if (mib == null) {
      return ('—', 'MiB');
    }
    return mib >= 1024
        ? ((mib / 1024).toStringAsFixed(1), 'GiB')
        : (_figure(mib), 'MiB');
  }

  static String _sizeText(double mib) {
    final (figure, unit) = _size(mib);
    return '$figure $unit';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `2026-11-04T21:58:07Z` as `2026-11-04 21:58 UTC`.
  static String _utc(String iso) {
    final t = DateTime.tryParse(iso)?.toUtc();
    if (t == null) {
      return iso;
    }
    return '${t.year}-${_two(t.month)}-${_two(t.day)} '
        '${_two(t.hour)}:${_two(t.minute)} UTC';
  }

  /// A time of day on this machine's clock, `01:12`.
  static String _clock(DateTime t) {
    final l = t.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// A log record's time as `02:01:44` (UTC, as the broker wrote it).
  static String _logTime(String iso) {
    final t = DateTime.tryParse(iso)?.toUtc();
    if (t == null) {
      return iso;
    }
    return '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  static String _duration(double s) {
    final d = Duration(seconds: s.round());
    if (d.inDays > 0) {
      return '${d.inDays} d ${d.inHours % 24} h';
    }
    if (d.inHours > 0) {
      return '${d.inHours} h ${d.inMinutes % 60} min';
    }
    return '${d.inMinutes} min';
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.pill,
    required this.stale,
    required this.meta,
    required this.tab,
    required this.tabs,
    required this.overview,
    required this.availability,
    required this.log,
    required this.maintenance,
    required this.attention,
    required this.polling,
    required this.onShow,
    required this.onHide,
    required this.onPoll,
    required this.onTab,
    required this.onMeasure,
    required this.onSource,
    required this.onLevel,
    required this.onFilter,
    required this.onLines,
    required this.onAuto,
    required this.onGetLog,
    required this.onCopyLog,
    required this.onSaveLog,
    required this.onLogLevel,
    required this.onClear,
    required this.onPutProfile,
    required this.onRemoveProfile,
    required this.onCopyCommand,
    required this.onTile,
    required this.onAttention,
    required this.onElsewhere,
    required this.onGuide,
  }) : super(
         equals: [
           site,
           pill,
           stale,
           meta,
           tab,
           tabs,
           overview,
           availability,
           log,
           maintenance,
           attention,
           polling,
         ],
       );

  final String site;
  final StatusPillVm pill;
  final bool stale;
  final String meta;
  final String tab;
  final List<PillTabVm> tabs;
  final SystemOverviewVm overview;
  final SystemAvailVm availability;
  final SystemLogVm log;
  final SystemMaintVm maintenance;
  final AttentionPanelVm attention;

  /// The Log tab reads again every 5 s.
  final bool polling;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onPoll;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onMeasure;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onLevel;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onLines;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGetLog;
  final void Function(BuildContext context) onCopyLog;
  final Future<void> Function(BuildContext context) onSaveLog;
  final ValueChanged<String> onLogLevel;
  final Future<void> Function(BuildContext context) onClear;
  final Future<void> Function(BuildContext context) onPutProfile;
  final Future<void> Function(BuildContext context, String name)
  onRemoveProfile;
  final void Function(BuildContext context, String id) onCopyCommand;
  final void Function(BuildContext context, String key) onTile;
  final void Function(BuildContext context, String id) onAttention;
  final void Function(BuildContext context, String id) onElsewhere;
  final void Function(BuildContext context) onGuide;
}
