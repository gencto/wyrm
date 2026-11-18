import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/warn_banner.dart';
import '../buttons/pill_tabs.dart';
import '../charts/traffic_card.dart';
import '../charts/trend.dart';
import '../charts/trend_format.dart';
import '../containers/attention_panel.dart';
import '../containers/command_card.dart';
import '../containers/guide_card.dart';
import '../containers/standby_pair.dart';
import '../containers/sys_tile.dart';
import '../forms/log_toolbar.dart';
import '../indicators/status_pill.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../overlays/confirm_dialog.dart';
import '../tables/log_table.dart';
import '../tables/row_list.dart';
import '../tables/term_table.dart';
import '../theme/sizes.dart';
import 'system_data.dart';
import 'system_page.dart';

/// System (specs/system.md) from typed values: it words them in the
/// language on screen and draws them with [SystemPage]. `Clear` and a
/// profile's `Remove` ask first, here; the rest reports to its callback.
class SystemScreen extends StatelessWidget {
  const SystemScreen({
    required this.vm,
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
    required this.onLines,
    required this.onAround,
    required this.onAuto,
    required this.onGetLog,
    required this.onCopyLog,
    required this.onSaveLog,
    required this.onLogLevel,
    required this.onClear,
    required this.onPutProfile,
    required this.onRemoveProfile,
    required this.onCopyCommand,
    required this.onBrokerUpdate,
    required this.onBackUp,
    required this.onRestore,
    required this.onOpenBackup,
    required this.onReadBackups,
    required this.onElsewhere,
    super.key,
  });

  /// The warm standby section of the operations guide.
  static const guideUrl =
      'https://github.com/gencto/wyrm/blob/main/docs/operations.md'
      '#warm-standby-adr-0036-option-3-stage-a';

  /// Where the commands of Maintenance point when Studio does not know the
  /// host's own paths (the broker serves neither).
  static const dataDir = '/var/lib/wyrm';
  static const configPath = '/etc/wyrm/wyrmd.json5';

  /// `arbiter_lease_s` at or below this is "renewing late" (proposed).
  static const leaseLate = 3;

  final SystemScreenVm vm;
  final ValueChanged<SysTab> onTab;
  final ValueChanged<SysTileKey> onTile;

  /// A card of the attention panel, by its place in [SystemScreenVm.attention].
  final ValueChanged<int> onAttention;
  final ValueChanged<SysMeasure> onMeasure;

  /// The traffic trend's window (µs), `Follow now` and `Reset zoom`.
  final RangeChanged<int> onTrafficWindow;
  final VoidCallback onTrafficFollow;
  final VoidCallback onTrafficReset;

  /// The action of Availability's banner: the audit record of the fork.
  final VoidCallback onBanner;

  /// The guide link of Availability: its address, to copy.
  final ValueChanged<String> onGuide;

  /// The Log toolbar: the source (null: the whole broker), the level, the
  /// filter (null: none), the lines, the time (null: every time), `every
  /// 5 s`, `Get log`.
  final ValueChanged<String?> onSource;
  final ValueChanged<SysLevel> onLevel;
  final ValueChanged<String?> onFilter;
  final ValueChanged<int> onLines;
  final ValueChanged<String?> onAround;
  final ValueChanged<bool> onAuto;
  final VoidCallback onGetLog;
  final VoidCallback onCopyLog;
  final VoidCallback onSaveLog;

  /// A level picked for the broker's own log.
  final ValueChanged<SysLevel> onLogLevel;

  /// `clear_conns`, once the user said yes.
  final VoidCallback onClear;
  final VoidCallback onPutProfile;

  /// A profile to remove, once the user said yes.
  final ValueChanged<String> onRemoveProfile;

  /// A command of Maintenance, to copy.
  final ValueChanged<String> onCopyCommand;
  final VoidCallback onBrokerUpdate;
  final VoidCallback onBackUp;
  final VoidCallback onRestore;
  final ValueChanged<String> onOpenBackup;
  final VoidCallback onReadBackups;
  final ValueChanged<SysElsewhere> onElsewhere;

  @override
  Widget build(BuildContext context) => SystemPage(
    title: S.current.wyrmdOn(vm.site),
    pill: StatusPillVm(
      label: vm.connected
          ? S.current.sysRunningActive
          : S.current.sysUnreachable,
      tone: vm.connected ? Tone.good : Tone.bad,
    ),
    meta: _meta(),
    stale: !vm.connected,
    tabsLabel: S.current.sysTabsLabel,
    tabs: [
      for (final t in SysTab.values)
        PillTabVm(
          id: _tabId(t),
          label: t.label,
          dot: t == SysTab.availability ? vm.standby?.dot : null,
        ),
    ],
    tab: _tabId(vm.tab),
    onTab: (id) {
      if (_tabOf[id] case final t?) {
        onTab(t);
      }
    },
    overview: _overview(),
    availability: _availability(),
    log: _log(),
    maintenance: _maintenance(),
    attention: _attention(),
    onAttention: (id) => onAttention(int.parse(id)),
    onTile: (key) {
      if (vm.tileOf(key) case final t?) {
        onTile(t);
      }
    },
    onMeasure: (id) {
      if (SysMeasure.values.asNameMap()[id] case final m?) {
        onMeasure(m);
      }
    },
    onTrafficWindow: onTrafficWindow,
    onTrafficFollow: onTrafficFollow,
    onTrafficReset: onTrafficReset,
    onBanner: onBanner,
    onGuide: () => onGuide(guideUrl),
    onSource: (s) => onSource(s.isEmpty ? null : s),
    onLevel: (id) {
      if (SysLevel.values.asNameMap()[id] case final l?) {
        onLevel(l);
      }
    },
    onFilter: (f) => onFilter(f.isEmpty ? null : f),
    onLines: onLines,
    onAround: (t) => onAround(t.isEmpty ? null : t),
    onAuto: onAuto,
    onGetLog: onGetLog,
    onCopyLog: onCopyLog,
    onSaveLog: onSaveLog,
    onLogLevel: (id) {
      if (SysLevel.values.asNameMap()[id] case final l?) {
        onLogLevel(l);
      }
    },
    onClear: () => _clear(context),
    onPutProfile: onPutProfile,
    onRemoveProfile: (name) => _removeProfile(context, name),
    onCopyCommand: (id) {
      if (_commands().where((c) => c.id == id).firstOrNull case final c?) {
        onCopyCommand(c.code);
      }
    },
    onBrokerUpdate: onBrokerUpdate,
    onBackUp: onBackUp,
    onRestore: onRestore,
    onOpenBackup: onOpenBackup,
    onReadBackups: onReadBackups,
    onElsewhere: (id) {
      if (SysElsewhere.values.asNameMap()[id] case final e?) {
        onElsewhere(e);
      }
    },
  );

  /// The [SysTab] of a tab id of [SystemPage].
  static final Map<String, SysTab> _tabOf = {
    for (final t in SysTab.values) _tabId(t): t,
  };

  /// The tab ids of [SystemPage], one per [SysTab].
  static String _tabId(SysTab t) => switch (t) {
    SysTab.overview => SystemPage.overviewTab,
    SysTab.availability => SystemPage.availabilityTab,
    SysTab.log => SystemPage.logTab,
    SysTab.maintenance => SystemPage.maintenanceTab,
  };

  // ---- words ---------------------------------------------------------------

  /// A count, `—` for none.
  static String _count(num? n) => n == null ? '—' : Formats.count(n);

  /// A measured figure, `—` for none.
  static String _figure(num? n) => n == null ? '—' : Formats.figure(n);

  /// A size in MiB as a tile shows it: its figure and unit.
  static (String, String) _size(num? mib) {
    if (mib == null) {
      return ('—', 'MiB');
    }
    final f = Formats.mebibyteFigure(mib);
    return (f.figure, f.unit);
  }

  /// `link:field-gw` and `broker:line2` as the name alone.
  static String _name(String cn) {
    final colon = cn.indexOf(':');
    return colon < 0 ? cn : cn.substring(colon + 1);
  }

  /// The value of [t] as a count.
  String _tileCount(SysTileKey t) => _count(vm.reading(t).value);

  // ---- the title row -------------------------------------------------------

  String _meta() {
    final b = vm.broker;
    final parts = [
      ?b.version,
      if (b.zenohVersion case final z?) 'Zenoh $z',
      ?b.distribution,
      if (b.started case final t?)
        S.current.sysMetaStarted(Formats.utcMinute(t)),
      if (b.uptime case final u?) S.current.upFor(Formats.runFor(u)),
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  // ---- Overview ------------------------------------------------------------

  SystemOverviewVm _overview() {
    final quarantined = vm.reading(SysTileKey.quarantined).value ?? 0;
    final (memory, memoryUnit) = _size(vm.reading(SysTileKey.memory).value);
    final (disk, diskUnit) = _size(vm.reading(SysTileKey.diskFree).value);
    final (data, dataUnit) = _size(vm.reading(SysTileKey.dataSize).value);
    SysTileVm tile(
      SysTileKey t, {
      required String value,
      String unit = '',
      String sub = '',
      Tone tone = Tone.neutral,
      Tone subTone = Tone.neutral,
      bool outlined = false,
    }) => SysTileVm(
      label: t.label,
      keyName: vm.reading(t).key,
      value: value,
      unit: unit,
      sub: sub,
      tone: tone,
      subTone: subTone,
      outlined: outlined,
      about: vm.reading(t).about,
      link: t.opens,
    );
    return SystemOverviewVm(
      groups: [
        TileGroupVm(
          label: S.current.sysGroupLinks,
          tiles: [
            tile(
              SysTileKey.linksConnected,
              value: _tileCount(SysTileKey.linksConnected),
              unit: switch (vm.linksTotal) {
                final t? => S.current.sysOfTotal(_count(t)),
                null => '',
              },
              sub: switch (vm.failedLink) {
                null => S.current.sysSubOpenLinks,
                final id => S.current.sysSubLinkFailed(id),
              },
              subTone: vm.failedLink == null ? Tone.neutral : Tone.bad,
            ),
            tile(
              SysTileKey.quarantined,
              value: _tileCount(SysTileKey.quarantined),
              sub: switch (vm.waitingLink) {
                null => S.current.sysSubOpenQuarantine,
                final cn => S.current.sysSubWaits(_name(cn)),
              },
              tone: quarantined > 0 ? Tone.warn : Tone.neutral,
              subTone: quarantined > 0 ? Tone.warn : Tone.neutral,
              outlined: quarantined > 0,
            ),
            tile(
              SysTileKey.packagesTotal,
              value: _tileCount(SysTileKey.packagesTotal),
              sub: S.current.sysSubPackages,
            ),
            tile(
              SysTileKey.upstreamConnected,
              value: _tileCount(SysTileKey.upstreamConnected),
              unit: S.current.sysUnitConnected,
              sub: switch (vm.upstreamPeer) {
                null => S.current.sysSubOpenSites,
                final p => S.current.sysSubPeer(p),
              },
            ),
            tile(
              SysTileKey.downstreamConnected,
              value: _tileCount(SysTileKey.downstreamConnected),
              unit: S.current.sysUnitConnected,
              sub: switch (vm.downstreamPeer) {
                null => S.current.sysSubOpenSites,
                final p => S.current.sysSubPeer(p),
              },
            ),
            tile(
              SysTileKey.sessions,
              value: _tileCount(SysTileKey.sessions),
              sub: S.current.sysSubSessions,
            ),
          ],
        ),
        TileGroupVm(
          label: S.current.sysGroupProcess,
          tiles: [
            tile(
              SysTileKey.cpu,
              value: _figure(vm.reading(SysTileKey.cpu).value),
              unit: vm.reading(SysTileKey.cpu).unit ?? '%',
              sub: S.current.sysSubCpu,
            ),
            tile(
              SysTileKey.memory,
              value: memory,
              unit: memoryUnit,
              sub: S.current.sysSubMemory,
            ),
            tile(
              SysTileKey.diskFree,
              value: disk,
              unit: diskUnit,
              sub: S.current.sysSubDisk,
            ),
            tile(
              SysTileKey.dataSize,
              value: data,
              unit: dataUnit,
              sub: switch (vm.historySize) {
                null => S.current.sysSubOpenHistory,
                final h => S.current.sysSubData(Formats.mebibyteText(h)),
              },
            ),
            tile(
              SysTileKey.aclDenied,
              value: _tileCount(SysTileKey.aclDenied),
              sub: S.current.sysSubAcl,
            ),
            tile(
              SysTileKey.auditRecords,
              value: _tileCount(SysTileKey.auditRecords),
              sub: S.current.sysSubAudit,
            ),
          ],
        ),
      ],
      traffic: _traffic(),
    );
  }

  TrafficCardVm _traffic() {
    final t = vm.traffic;
    final m = t.measure;
    final unit = m.unitOr(t.unit);
    String now(num? v) => v == null ? '—' : Formats.figure(v * m.scale);
    return TrafficCardVm(
      title: S.current.sysTraffic,
      measures: [
        for (final s in SysMeasure.values)
          PillTabVm(id: s.name, label: s.label),
      ],
      measure: m.name,
      inLabel: S.current.sysIn,
      outLabel: S.current.sysOut,
      inKey: t.inKey,
      outKey: t.outKey,
      inNow: now(t.inNow),
      outNow: now(t.outNow),
      unit: unit,
      trend: switch (t.window) {
        final w? when t.samples.length >= 2 => _trafficTrend(t, w, unit),
        _ => null,
      },
      note: S.current.sysTrafficNote,
      empty: S.current.sysCollecting,
    );
  }

  /// The ring of samples as a live trend (spec trend.md §4): in and out,
  /// the window following now until the user moves it.
  TrendVm _trafficTrend(SysTrafficData t, SysTrendWindow w, String unit) {
    final m = t.measure;
    List<TrendSample> line({required bool inward}) => [
      for (final s in t.samples)
        TrendSample(s.time, m.scale * (inward ? s.inward : s.outward)),
    ];
    final ins = line(inward: true);
    final outs = line(inward: false);
    bool whole(List<TrendSample> l) =>
        l.every((p) => p.v == p.v!.roundToDouble());
    final decimals = whole(ins) && whole(outs) ? 0 : 1;
    DateTime at(int us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
    return TrendVm(
      title: S.current.sysTrafficDescribe(
        m.label,
        Formats.clock(at(t.samples.first.time)),
        Formats.clock(at(t.samples.last.time)),
      ),
      series: [
        TrendSeriesVm(
          id: 'in',
          name: t.inKey,
          label: S.current.sysIn,
          color: .good,
          unit: unit,
          decimals: decimals,
          samples: ins,
          overview: ins,
        ),
        TrendSeriesVm(
          id: 'out',
          name: t.outKey,
          label: S.current.sysOut,
          color: .text4,
          unit: unit,
          decimals: decimals,
          samples: outs,
          overview: outs,
        ),
      ],
      rangeStart: w.rangeStart,
      rangeEnd: w.rangeEnd,
      windowStart: w.windowStart,
      windowEnd: w.windowEnd,
      minWindow: w.minWindow,
      endsNow: true,
      live: true,
      following: w.following,
      card: false,
      legend: false,
      hint: false,
      plotHeight: AppSizes.trafficPlot,
      format: trendFormat(),
    );
  }

  // ---- Availability --------------------------------------------------------

  SystemAvailVm _availability() {
    final name = vm.site;
    final standby = vm.standby;
    if (standby == null || standby == SysStandby.none) {
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
    final behind = standby == SysStandby.behind;
    final lag = vm.reading(SysTileKey.standbyLag).value ?? 0;
    final forks = vm.reading(SysTileKey.standbyForks).value ?? 0;
    final lease = vm.reading(SysTileKey.arbiterLease).value ?? 0;
    final late = lease > 0 && lease <= leaseLate;
    SysTileVm tile(
      SysTileKey t, {
      required String value,
      required String sub,
      String unit = '',
      Tone tone = Tone.neutral,
      Tone subTone = Tone.neutral,
      bool outlined = false,
    }) => SysTileVm(
      label: t.label,
      keyName: vm.reading(t).key,
      value: value,
      unit: unit,
      sub: sub,
      tone: tone,
      subTone: subTone,
      outlined: outlined,
      about: vm.reading(t).about,
    );
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
        tile(
          SysTileKey.standbyConnected,
          value: _tileCount(SysTileKey.standbyConnected),
          sub: S.current.sysSubFollows,
          tone: Tone.good,
        ),
        tile(
          SysTileKey.standbyLag,
          value: _count(lag),
          unit: S.current.sysRecords,
          sub: lag > 0 ? S.current.sysSubLag : S.current.sysSubLagNone,
          tone: lag > 0 ? Tone.warn : Tone.neutral,
          subTone: lag > 0 ? Tone.warn : Tone.neutral,
          outlined: lag > 0,
        ),
        tile(
          SysTileKey.arbiterLease,
          value: lease > 0 ? _count(lease) : '—',
          unit: lease > 0 ? S.current.sysSecondsLeft : '',
          sub: lease <= 0
              ? S.current.sysSubNoArbiter
              : (late ? S.current.sysSubLeaseLate : S.current.sysSubLease),
          tone: late ? Tone.warn : Tone.neutral,
          subTone: late ? Tone.warn : Tone.neutral,
        ),
        tile(
          SysTileKey.standbyForks,
          value: _count(forks),
          unit: S.current.sysSinceStart,
          sub: forks > 0 ? S.current.sysSubForks : S.current.sysSubForksNone,
          tone: forks > 0 ? Tone.bad : Tone.neutral,
          subTone: forks > 0 ? Tone.bad : Tone.neutral,
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

  /// The order of the Log toolbar's level list (board `SystemLog`).
  static const List<SysLevel> _toolbarLevels = [
    SysLevel.info,
    SysLevel.warn,
    SysLevel.error,
    SysLevel.debug,
    SysLevel.trace,
  ];

  SystemLogVm _log() {
    final l = vm.log;
    final reason = l.reason?.text;
    final around = l.around;
    final rows = reason == null
        ? [
            for (final line in l.lines)
              LogRowVm(
                time: switch (line.at) {
                  final t? => Formats.utcClockSeconds(t),
                  null => line.time,
                },
                level: line.level?.label.toUpperCase() ?? '',
                target: line.target,
                message: line.message,
              ),
          ]
        : const <LogRowVm>[];
    final error = reason == null ? l.error?.text : null;
    return SystemLogVm(
      toolbar: LogToolbarVm(
        sourceLabel: S.current.sysSource,
        sources: [
          ChoiceItemVm(value: '', label: S.current.sysBrokerAll),
          for (final id in l.sources)
            ChoiceItemVm(value: id, label: S.current.sysLinkSource(id)),
        ],
        source: l.source ?? '',
        levelLabel: S.current.sysLevelMore,
        levels: [
          for (final v in _toolbarLevels)
            ChoiceItemVm(value: v.name, label: v.label),
        ],
        level: l.level.name,
        filterLabel: S.current.sysFilter,
        filterHint: S.current.sysFilterHint,
        filter: l.filter ?? '',
        linesLabel: S.current.sysLines,
        lines: l.count,
        autoLabel: S.current.sysEvery5s,
        auto: l.auto,
        getLabel: S.current.sysGetLog,
        aroundLabel: S.current.sysAround,
        aroundHint: S.current.sysAroundHint,
        around: around ?? '',
        aroundClear: S.current.sysAroundClear,
        aroundBad: S.current.sysAroundBad,
        disabledReason: reason,
      ),
      summary: reason == null
          ? (around == null
                ? S.current.sysLogSummary(rows.length)
                : S.current.sysLogSummaryAround(rows.length, l.held, around))
          : S.current.sysLogSummaryNone,
      copyLabel: S.current.sysCopy,
      saveLabel: S.current.sysSaveLog,
      rows: rows,
      message:
          error ??
          (reason == null
              ? (l.reading
                    ? '…'
                    : (around != null && l.held > 0
                          ? S.current.sysNoLinesAround(l.held, around)
                          : S.current.sysNoLines))
              : S.current.sysLogNeedsConfig),
      bad: error != null,
      levelTitle: S.current.sysBrokerLogLevel,
      levelKey: 'sys/log_level',
      levelNote: S.current.sysLogLevelNote,
      levels: [
        for (final v in SysLevel.values) PillTabVm(id: v.name, label: v.label),
      ],
      level: l.brokerLevel.name,
      levelReason: reason,
    );
  }

  // ---- Maintenance ---------------------------------------------------------

  List<CommandCardVm> _commands() {
    final slash = dataDir.lastIndexOf('/');
    final parent = dataDir.substring(0, slash);
    final dir = dataDir.substring(slash + 1);
    final name = vm.site.isEmpty ? 'site' : vm.site;
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
        code: 'wyrmd -c $configPath verify',
        note: S.current.sysCmdVerifyNote,
        copyLabel: S.current.sysCopyCommand(S.current.sysCmdVerify),
      ),
      CommandCardVm(
        id: 'check',
        title: S.current.sysCmdCheck,
        code: 'wyrmd -c $configPath check',
        note: S.current.sysCmdCheckNote,
        copyLabel: S.current.sysCopyCommand(S.current.sysCmdCheck),
      ),
    ];
  }

  /// The card *Broker version*: the one way into the broker update.
  BrokerVersionCardVm? _version(String? reason) =>
      switch (vm.maintenance.version) {
        null => null,
        final v => BrokerVersionCardVm(
          title: S.current.bupCard,
          line: switch (v.state) {
            SysSelfUpdate.trial => S.current.bupCardTrial(v.version),
            SysSelfUpdate.rolledBack => S.current.bupCardRolledBack(v.version),
            SysSelfUpdate.idle when v.newer => S.current.bupCardAvailable(
              v.version,
              v.latest,
            ),
            SysSelfUpdate.idle => S.current.bupCardCurrent(v.version),
          },
          tone: switch (v.state) {
            SysSelfUpdate.rolledBack => Tone.warn,
            _ when v.newer => Tone.ember,
            SysSelfUpdate.idle || SysSelfUpdate.trial => Tone.neutral,
          },
          action: v.runs || !v.newer ? S.current.bupShow : S.current.bupUpdate,
          reason: reason,
        ),
      };

  /// The card *Backups*: null for a broker without `sys/backups`.
  BackupsCardVm? _backups(String? reason) => switch (vm.maintenance.backups) {
    null => null,
    final b => BackupsCardVm(
      title: S.current.bakCard,
      note: b.state.said ?? S.current.bakCardNote(b.keepDays),
      empty: S.current.bakCardEmpty,
      backUpLabel: S.current.bakBackUp,
      restoreLabel: S.current.bakRestore,
      reason: b.state.said ?? reason,
      readAgainLabel: b.state == SysBackupsState.failed
          ? S.current.bakReadAgain
          : null,
      // not read: no list, so the card does not say "none is kept"
      rows: b.state != SysBackupsState.read
          ? null
          : [
              // a backup Studio could not read is there, and says so
              for (final id in b.unread)
                RowItemVm(id: id, title: id, subtitle: S.current.bakRowNotRead),
              for (final j in b.rows)
                RowItemVm(
                  id: j.id,
                  title: j.name,
                  subtitle: [
                    j.kind.label(j.link),
                    [for (final s in j.sections) s.label].join(', '),
                    if (j.created case final t?) Formats.dateTime(t),
                  ].join(' · '),
                  trailing: switch (j.state) {
                    SysBackupState.running => S.current.bakRowRunning(
                      j.progress,
                    ),
                    SysBackupState.failed => S.current.bakRowFailed,
                    _ when j.sending => S.current.bakRowSending(j.sendProgress),
                    SysBackupState.pending ||
                    SysBackupState.done => Formats.bytes(j.size),
                  },
                  action: S.current.bakOpen,
                  actionHint: '${S.current.bakOpen} ${j.name}',
                ),
            ],
    ),
  };

  SystemMaintVm _maintenance() {
    final m = vm.maintenance;
    final reason = m.reason?.text;
    final stale = m.stale;
    final busy = m.busy ? '…' : null;
    final unlisted = m.profilesUnlisted;
    return SystemMaintVm(
      staleTitle: S.current.sysStale,
      staleNote: S.current.sysStaleNote,
      stale: [
        for (final l in stale)
          RowItemVm(
            id: l.id,
            title: l.id,
            subtitle: S.current.sysStaleRow(l.cn ?? 'link:${l.id}'),
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
        for (final p in m.profiles)
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
      backups: _backups(reason),
      version: _version(reason),
      backupTitle: m.backups == null
          ? S.current.sysBackup
          : S.current.bakOffline,
      backupNote: m.backups != null
          ? S.current.bakOfflineNote
          : switch (m.dataSize) {
              null => S.current.sysBackupNoteNoSize,
              final d => S.current.sysBackupNote(Formats.mebibyteText(d)),
            },
      commands: _commands(),
      backupWarning: S.current.sysBackupWarning,
      elsewhereLabel: S.current.sysElsewhere,
      elsewhere: [
        for (final e in SysElsewhere.values)
          // the gallery of the design system, in development builds only
          if (e != SysElsewhere.gallery || kDebugMode)
            ElsewhereVm(id: e.name, label: e.label),
      ],
    );
  }

  /// `clear_conns` asks first, with the ids it would remove.
  Future<void> _clear(BuildContext context) async {
    final ids = [for (final l in vm.maintenance.stale) l.id];
    if (ids.isEmpty) {
      return;
    }
    if (await ConfirmDialog.ask(
      context,
      title: S.current.sysClearAsk,
      message: S.current.sysClearAskBody(ids.join(', ')),
      confirm: S.current.sysClearConfirm,
      cancel: S.current.cancel,
    )) {
      onClear();
    }
  }

  Future<void> _removeProfile(BuildContext context, String name) async {
    if (await ConfirmDialog.ask(
      context,
      title: S.current.sysRemoveProfile(name),
      message: S.current.sysRemoveProfileAsk(name),
      confirm: S.current.sysRemove,
      cancel: S.current.cancel,
    )) {
      onRemoveProfile(name);
    }
  }

  // ---- the attention panel -------------------------------------------------

  AttentionPanelVm _attention() {
    final items = [
      for (final (i, a) in vm.attention.indexed)
        AttentionItemVm(
          id: '$i',
          title: switch (a.kind) {
            SysAttention.standbyBehind =>
              a.count > 0
                  ? S.current.sysAttnBehind(_count(a.count))
                  : S.current.sysAttnFork,
            SysAttention.linkFailed => S.current.sysAttnLinkFailed(a.subject),
            SysAttention.quarantine => S.current.sysAttnQuarantine(
              _name(a.name),
            ),
            SysAttention.brokerWaiting => S.current.sysAttnBroker(
              _name(a.name),
            ),
            SysAttention.waitingNotRead => S.current.sysAttnNotRead(
              _name(a.name),
            ),
            SysAttention.aclGrown => S.current.sysAttnAcl(_count(a.count)),
            SysAttention.noStandby => S.current.sysAttnNoStandby,
          },
          detail: switch (a.kind) {
            SysAttention.standbyBehind =>
              a.more > 0
                  ? S.current.sysAttnBehindDetail(a.more)
                  : S.current.sysAttnBehindPlain,
            SysAttention.linkFailed => S.current.sysAttnLinkDetail(a.subject),
            SysAttention.quarantine => switch (a.since) {
              final t? => S.current.sysAttnQuarantineSince(
                a.name,
                Formats.clock(t),
              ),
              null => S.current.sysAttnQuarantineDetail(a.name),
            },
            SysAttention.brokerWaiting =>
              a.count == 0
                  ? S.current.sysAttnBrokerPlain
                  : S.current.sysAttnBrokerRelays(a.count),
            SysAttention.waitingNotRead => S.current.waitNotReadNote,
            SysAttention.aclGrown => S.current.sysAttnAclDetail(
              _count(a.more),
            ),
            SysAttention.noStandby => S.current.sysAttnNoStandbyDetail,
          },
          go: a.kind.go,
          tone: a.kind.tone,
        ),
    ];
    final name = vm.site;
    final b = vm.broker;
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
          dot: vm.connected ? Tone.good : Tone.bad,
        ),
        BrokerFactVm(
          label: S.current.factStarted,
          value: switch (b.started) {
            final t? => Formats.utcMinute(t),
            null => '—',
          },
        ),
        BrokerFactVm(
          label: S.current.factBuild,
          value: switch ([?b.version, ?b.distribution]) {
            [] => '—',
            final parts => parts.join(' · '),
          },
        ),
      ],
    );
  }
}
