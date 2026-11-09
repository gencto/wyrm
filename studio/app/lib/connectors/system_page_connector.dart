import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/redux/system/actions/set_log_level_action.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/containers/metric_card.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/system_page.dart';

import '../common/tab_visibility.dart';
import '../dialogs/node_action_dialog.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

const _logLevels = ['error', 'warn', 'info', 'debug', 'trace'];

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
      child: SystemPage(
        title: S.current.wyrmdOn(vm.site),
        subtitle: vm.subtitle,
        pill: StatusPillVm(label: S.current.running, tone: Tone.good),
        metrics: vm.metrics,
        ratesTitle: S.current.messagesPerSecond,
        rates: vm.rates,
        rateLabels: const ['in', 'out'],
        ratesEmpty: S.current.collecting,
        logTitle: S.current.brokerLog,
        levels: [for (final l in _logLevels) TabItemVm(id: l, label: l)],
        level: vm.level,
        onLevel: vm.onLevel,
        log: vm.log,
        logEmpty: S.current.logEmpty,
        loadingLog: vm.loadingLog,
        inspector: vm.inspector,
        onAction: (a) => vm.onAction(context, a),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SystemPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _sys => '${site.root}/sys';

  List<String> get _watch => ['$_sys/*'];

  String? _v(String k) => switch (live.values['$_sys/$k']?.value) {
    null => null,
    final double d => d.toStringAsFixed(d.abs() >= 100 ? 0 : 1),
    final Object o => '$o',
  };

  double? _n(String k) => switch (live.values['$_sys/$k']?.value) {
    final num n => n.toDouble(),
    _ => null,
  };

  @override
  _Vm fromStore() {
    final linksTotal = _v('links_total') ?? '—';
    final quarantined = _n('quarantined') ?? 0;
    final standby = _n('standby_connected');
    final reason = site.needs('config', _sys);
    return _Vm(
      site: site.viewed ?? '',
      subtitle: [
        if (_v('zenoh_version') case final z?) 'Zenoh $z',
        if (_v('version') case final v?) 'wyrmd $v',
        if (_n('uptime') case final u?) S.current.upFor(_duration(u)),
        S.current.sysAdminOnly,
      ].join(' · '),
      metrics: [
        MetricVm(
          label: S.current.mLinksConnected,
          value: '${_v('links_connected') ?? '—'} / $linksTotal',
        ),
        MetricVm(
          label: S.current.mInQuarantine,
          value: quarantined.toStringAsFixed(0),
          tone: quarantined > 0 ? Tone.warn : Tone.neutral,
          sub: S.current.seeLinks,
        ),
        MetricVm(label: S.current.mSessions, value: _v('sessions') ?? '—'),
        MetricVm(
          label: S.current.mAclDenials,
          value: _v('acl_denied') ?? '—',
          tone: (_n('acl_denied') ?? 0) > 0 ? Tone.warn : Tone.neutral,
        ),
        MetricVm(
          label: 'CPU',
          value: _n('cpu') == null ? '—' : '${_v('cpu')} %',
        ),
        MetricVm(label: S.current.mMemory, value: _bytes(_n('memory'))),
        MetricVm(
          label: S.current.mFreeDisk,
          value: _bytes(_n('disk_free')),
          sub: S.current.dataDir(_bytes(_n('data_size'))),
        ),
        MetricVm(
          label: S.current.mAuditRecords,
          value: _v('audit_records') ?? '—',
        ),
        MetricVm(
          label: S.current.mUpDown,
          value:
              '${_v('upstream_connected') ?? '—'} / ${_v('downstream_connected') ?? '—'}',
        ),
        if (standby != null)
          MetricVm(
            label: S.current.mStandby,
            value: standby > 0 ? S.current.connected : S.current.none,
            sub: _v('standby_lag') == null
                ? ''
                : S.current.lag(_v('standby_lag')!),
          ),
      ],
      rates: [_n('messages_in_per_second'), _n('messages_out_per_second')],
      level: system.logLevel ?? 'info',
      log: system.log.unlock,
      loadingLog: system.isWaiting,
      inspector: DetailInspectorVm(
        eyebrow: S.current.controlPlane,
        title: site.viewed ?? '',
        keyName: 'sys',
        facts: [
          FactVm(
            label: S.current.factLogLevel,
            value: _v('log_level') ?? '—',
            mono: true,
          ),
          FactVm(
            label: S.current.allowAllLinks,
            value: _v('allow_all_links') ?? '—',
            mono: true,
          ),
          FactVm(
            label: S.current.holdUnknown,
            value: _v('enable_quarantine') ?? '—',
            mono: true,
          ),
          if (_v('start_time') case final t?)
            FactVm(label: S.current.factStarted, value: t),
          if (_v('distribution') case final d?)
            FactVm(label: S.current.factBuild, value: d),
        ],
        groups: [
          ActionGroupVm(
            label: S.current.groupChange,
            actions: [
              for (final l in _logLevels)
                if (l != _level)
                  ActionRowVm(
                    id: 'level:$l',
                    icon: 'action_log',
                    title: S.current.setLogLevel(l),
                    description: S.current.setLogLevelNote,
                    code: 'sys/log_level',
                    disabledReason: reason,
                  ),
            ],
          ),
          ActionGroupVm(
            label: S.current.groupWork,
            actions: [
              ActionRowVm(
                id: 'clear_conns',
                icon: 'action_trash',
                title: S.current.clearConns,
                description: S.current.clearConnsNote,
                code: 'clear_conns',
                disabledReason: reason,
              ),
              if (kDebugMode)
                ActionRowVm(
                  id: 'gallery',
                  icon: 'ws_system',
                  title: S.current.designGallery,
                  description: S.current.designGalleryNote,
                  code: 'dev',
                ),
            ],
          ),
        ],
        footer: S.current.systemFooter,
      ),
      onShow: () {
        dispatchSync(WatchKeysAction(_watch));
        unawaited(dispatchAndWait(RetrieveSystemLogAction()));
      },
      onHide: () => dispatchSync(UnwatchKeysAction(_watch)),
      onLevel: (l) {
        dispatchSync(SetLogLevelAction(l));
        unawaited(dispatchAndWait(RetrieveSystemLogAction()));
      },
      onAction: (context, a) async {
        if (a.startsWith('level:')) {
          dispatchSync(
            StageValueAction(
              '$_sys/log_level',
              a.substring(6),
              from: _v('log_level') ?? '—',
            ),
          );
        } else if (a == 'clear_conns') {
          await runNodeAction(
            context,
            _sys,
            'clear_conns',
            confirm: S.current.clearConnsNote,
          );
        } else if (a == 'gallery') {
          dispatch(GoAction.push(const GalleryRoute()));
        }
      },
    );
  }

  /// `memory`, `disk_free` and `data_size` are in MiB.
  static String _bytes(double? n) {
    if (n == null) {
      return '—';
    }
    return n >= 1024
        ? '${(n / 1024).toStringAsFixed(1)} GiB'
        : '${n.toStringAsFixed(n < 10 ? 1 : 0)} MiB';
  }

  /// `sys/log_level` is an enum code of `error`…`trace`.
  String? get _level => switch (live.values['$_sys/log_level']?.value) {
    null => null,
    final Object v => valueText(v, choices: _logLevels),
  };

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
    required this.subtitle,
    required this.metrics,
    required this.rates,
    required this.level,
    required this.log,
    required this.loadingLog,
    required this.inspector,
    required this.onShow,
    required this.onHide,
    required this.onLevel,
    required this.onAction,
  }) : super(
         equals: [
           site,
           subtitle,
           metrics,
           rates,
           level,
           log,
           loadingLog,
           inspector,
         ],
       );

  final String site;
  final String subtitle;
  final List<MetricVm> metrics;
  final List<double?> rates;
  final String level;
  final List<String> log;
  final bool loadingLog;
  final DetailInspectorVm inspector;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onLevel;
  final Future<void> Function(BuildContext context, String action) onAction;
}
