import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/deauthorize_link_action.dart';
import 'package:business/redux/links/actions/remove_link_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/set_selected_link_action.dart';
import 'package:business/redux/links/actions/set_tab_action.dart';
import 'package:business/redux/links/actions/start_link_action.dart';
import 'package:business/redux/links/actions/stop_link_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/packages/actions/retrieve_packages_action.dart';
import 'package:business/redux/quarantine/actions/approve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/reject_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/set_admission_options_action.dart';
import 'package:business/redux/quarantine/actions/set_selected_entry_action.dart';
import 'package:business/redux/updates/actions/close_update_action.dart';
import 'package:business/redux/updates/actions/open_update_action.dart';
import 'package:business/redux/updates/actions/rollback_package_action.dart';
import 'package:business/redux/updates/actions/set_accept_new_action.dart';
import 'package:business/redux/updates/actions/set_auto_rollback_action.dart';
import 'package:business/redux/updates/actions/set_take_point_action.dart';
import 'package:business/redux/updates/actions/update_package_action.dart';
import 'package:business/wyrm/mappers/link_info_mapper.dart';
import 'package:business/wyrm/mappers/package_info_mapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/links_tab.dart';
import 'package:models/package_info.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/restore_point.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/pages/links_page.dart';
import 'package:ui/tables/row_table.dart';

import '../common/forms.dart';
import '../common/tab_visibility.dart';
import '../common/update_sheets.dart';
import '../dialogs/link_dialogs.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class LinksPageConnector extends StatelessWidget {
  const LinksPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: LinksPage(
        title: S.current.linksOn(vm.site),
        subtitle: S.current.linksSubtitle,
        addLabel: S.current.addALink,
        onTapLinkInstall: vm.addReason == null ? vm.onTapLinkInstall : null,
        addReason: vm.addReason,
        tabs: vm.tabs,
        tab: vm.tab,
        description: vm.description,
        settings: vm.settings,
        columns: vm.columns,
        rows: vm.rows,
        empty: vm.empty,
        inspector: vm.inspector,
        busy: vm.busy,
        onTab: vm.onTab,
        onRow: vm.onRow,
        onAction: (a) => vm.onAction(context, a),
        onSubmit: vm.onSubmit,
        onSecondary: () => vm.onAction(context, 'reject'),
        secondLabel: vm.updateAll ? S.current.updAllOfficial : null,
        secondReason: vm.addReason,
        onSecond: () => vm.onAction(context, 'update-all'),
        sheet: vm.sheet,
        onSheetPrimary: () => vm.onAction(context, 'sheet-primary'),
        onSheetSecondary: () => vm.onAction(context, 'sheet-secondary'),
        onSheetToggle: vm.onSheetToggle,
        onSheetAction: (a) => vm.onAction(context, 'sheet-$a'),
        onSheetClose: () => vm.onAction(context, 'sheet-close'),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LinksPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _root => site.root ?? '';

  List<String> get _watch => [
    '$_root/sys/links/*/state',
    '$_root/sys/enable_quarantine',
    '$_root/sys/allow_all_links',
    // What moves while a package is updated (ADR 0048 §1).
    '$_root/sys/packages/*/*',
    '$_root/sys/links/*/restore_points',
  ];

  /// The package [name] with its live values, or null when not installed.
  PackageInfo? _pkg(String? name) {
    final p = name == null ? null : packages.table[name];
    return p == null
        ? null
        : packageLive(
            p,
            (leaf) => live.values['$_root/sys/packages/$name/$leaf']?.value,
          );
  }

  /// The package a link runs, or null for a built-in driver.
  static String? _packageOf(LinkInfo l) =>
      l.driver.startsWith('pkg:') ? l.driver.substring(4) : null;

  /// The links that run the package [name], by id.
  List<String> _linksOf(String name) => [
    for (final id in links.view)
      if (links.table[id]?.driver == 'pkg:$name') id,
  ];

  /// The repository lists it: `latest` is empty for a custom package.
  static bool _isOfficial(PackageInfo p) => p.latest.isNotEmpty;

  List<RestorePoint> _points(String link) => restorePointsOf(
    live.values['$_root/sys/links/$link/restore_points']?.value,
  );

  /// The official packages with a newer version, in the order of the links.
  List<String> get _updatable => {
    for (final id in links.view)
      if (_pkg(_packageOf(links.table[id]!)) case final p?
          when p.updateAvailable)
        p.name,
  }.toList();

  UpdateSheetData? get _sheetData {
    final p = _pkg(updates.package);
    if (p == null) {
      return null;
    }
    final ids = _linksOf(p.name);
    final row = linkInstall.catalog
        .where((c) => c.id == 'package:${p.name}')
        .firstOrNull;
    return UpdateSheetData(
      package: p,
      links: ids,
      follow: updates.view != 'review',
      official: _isOfficial(p),
      title: row?.name,
      summary: row?.description,
      takePoint: updates.takePoint,
      autoRollback: updates.autoRollback,
      acceptNew: updates.acceptNew,
      asks: updates.asks,
      said: updates.message,
      busy: updates.isWaiting,
      rollingBack: updates.isRollingBack,
      seenAt: updates.seenAt,
      points: [
        for (final id in ids)
          for (final point in _points(id)) (id, point),
      ]..sort((a, b) => b.$2.at.compareTo(a.$2.at)),
      queue: updates.queue.unlock,
      reason: site.needs('config', '$_root/sys/links'),
    );
  }

  /// A link's state: its live value, else the table's.
  String _state(LinkInfo l) =>
      switch (live.values['$_root/sys/links/${l.id}/state']) {
        final v? => linkStateOf(v.value),
        null => l.state,
      };

  bool _external(LinkInfo l) => l.mode == LinkMode.external;

  @override
  _Vm fromStore() {
    final viewed = site.viewed ?? '';
    final all = [for (final id in links.view) ?links.table[id]];
    final local = all.where((l) => !_external(l)).toList();
    final remote = all.where(_external).toList();
    final waiting = [for (final n in quarantine.view) ?quarantine.table[n]];
    final updatable = _updatable;
    // The rows of Updates: the links of a package with a newer version,
    // and the links of a custom package (updated from a file).
    final toUpdate = [
      for (final l in local)
        if (_pkg(_packageOf(l)) case final p?
            when p.updateAvailable || !_isOfficial(p))
          l,
    ];
    final updateCount = toUpdate
        .where((l) => _pkg(_packageOf(l))!.updateAvailable)
        .length;
    // Hidden at 0 (spec §1): the attribute of `sys/links` until the live
    // values of the packages arrive.
    final showUpdates =
        updateCount > 0 ||
        links.updatesAvailable > 0 ||
        links.tab == LinksTab.updates;
    final tab = links.tab;
    final sheet = _sheetData;
    final configReason = site.needs('config', '$_root/sys/links');
    return _Vm(
      site: viewed,
      addReason: configReason,
      tab: tab.name,
      tabs: [
        TabItemVm(
          id: LinksTab.local.name,
          label: S.current.onThisBroker,
          count: '${local.length}',
        ),
        if (showUpdates)
          TabItemVm(
            id: LinksTab.updates.name,
            label: S.current.updTab,
            count: '${updateCount > 0 ? updateCount : links.updatesAvailable}',
            countTone: Tone.ember,
          ),
        TabItemVm(
          id: LinksTab.remote.name,
          label: S.current.onOtherDevices,
          count: '${remote.length}',
        ),
        TabItemVm(
          id: LinksTab.quarantine.name,
          label: S.current.quarantine,
          count: '${waiting.length}',
          countTone: waiting.isEmpty ? Tone.neutral : Tone.warn,
        ),
      ],
      description: switch (tab) {
        LinksTab.local => S.current.linksLocalNote(viewed),
        LinksTab.updates => S.current.updTabNote,
        LinksTab.remote => S.current.linksRemoteNote,
        LinksTab.quarantine => S.current.linksQuarantineNote,
      },
      settings: tab == LinksTab.quarantine ? _settings() : const [],
      columns: switch (tab) {
        LinksTab.local => [
          ColumnVm(S.current.colLink, flex: 3),
          ColumnVm(S.current.colVersionSource, flex: 3),
          ColumnVm(S.current.colRunsAs, flex: 2),
          ColumnVm(S.current.colState, flex: 3),
        ],
        LinksTab.updates => [
          ColumnVm(S.current.colLink, flex: 3),
          ColumnVm(S.current.updColPackage, flex: 3),
          ColumnVm(S.current.updColVersion, flex: 2),
          ColumnVm(S.current.colState, flex: 3),
        ],
        LinksTab.remote => [
          ColumnVm(S.current.colLinkDevice, flex: 3),
          ColumnVm(S.current.colCertificate, flex: 3),
          ColumnVm(S.current.colMode, flex: 2),
          ColumnVm(S.current.colState, flex: 3),
        ],
        LinksTab.quarantine => [
          ColumnVm(S.current.colWho, flex: 3),
          ColumnVm(S.current.colFrom, flex: 3),
          ColumnVm(S.current.colWhyHere, flex: 2),
          ColumnVm(S.current.colState, flex: 3),
        ],
      },
      rows: switch (tab) {
        LinksTab.local => [for (final l in local) _localRow(l)],
        LinksTab.updates => [for (final l in toUpdate) _updateRow(l)],
        LinksTab.remote => [for (final l in remote) _remoteRow(l)],
        LinksTab.quarantine => [for (final q in waiting) _quarantineRow(q)],
      },
      empty: switch (tab) {
        _ when links.isWaiting && all.isEmpty => S.current.loading,
        LinksTab.local => S.current.noLocalLinks,
        LinksTab.updates => S.current.updNothing,
        LinksTab.remote => S.current.noRemoteLinks,
        LinksTab.quarantine => S.current.nothingInQuarantine,
      },
      inspector: _inspector(tab),
      updateAll: tab == LinksTab.updates && updatable.isNotEmpty,
      sheet: sheet == null ? null : updateSheet(sheet),
      onSheetToggle: (id, {required value}) => switch (id) {
        'point' => dispatchSync(SetTakePointAction(value)),
        'auto' => dispatchSync(SetAutoRollbackAction(value)),
        _ => dispatchSync(SetAcceptNewAction(value)),
      },
      busy: links.isActing || quarantine.isWaiting,
      onShow: () {
        unawaited(dispatchAndWait(WatchKeysAction(_watch)));
        unawaited(dispatchAndWait(RetrieveLinksAction()));
        unawaited(dispatchAndWait(RetrieveQuarantineAction()));
        unawaited(dispatchAndWait(RetrievePackagesAction()));
      },
      onHide: () => dispatch(UnwatchKeysAction(_watch)),
      onTapLinkInstall: () => dispatch(GoAction.push(const LinkInstallRoute())),
      onTab: (t) => dispatch(SetTabAction(LinksTab.values.byName(t))),
      onRow: (id) {
        if (tab == LinksTab.quarantine) {
          dispatchSync(SetSelectedEntryAction(id));
        } else if (tab == LinksTab.updates) {
          final p = _pkg(_packageOf(links.table[id]!));
          if (p != null) {
            dispatchSync(
              OpenUpdateAction(
                p.name,
                follow: p.lastUpdate?.result == 'checking',
              ),
            );
          }
        } else {
          dispatchSync(SetSelectedLinkAction(id));
        }
      },
      onAction: _onAction,
      onSubmit: (args) {
        final node = quarantine.selectedEntry;
        return node == null
            ? null
            : sendForm(
                dispatchAndWait(ApproveQuarantineAction(node, plainArgs(args))),
              );
      },
    );
  }

  List<SettingCardVm> _settings() {
    bool value(String k) => live.values['$_root/sys/$k']?.value == true;
    final reason = site.needs('config', '$_root/sys');
    return [
      SettingCardVm(
        title: S.current.holdUnknown,
        description: S.current.holdUnknownNote,
        keyName: 'sys/enable_quarantine',
        disabledReason: reason,
        value: FieldVm(
          value: value('enable_quarantine'),
          enabled: reason == null,
          onChanged: (v) => dispatch(SetAdmissionOptionsAction(holdUnknown: v)),
        ),
      ),
      SettingCardVm(
        title: S.current.allowAllLinks,
        description: S.current.allowAllLinksNote,
        keyName: 'sys/allow_all_links',
        disabledReason: reason,
        value: FieldVm(
          value: value('allow_all_links'),
          enabled: reason == null,
          onChanged: (v) => dispatch(SetAdmissionOptionsAction(allowAll: v)),
        ),
      ),
    ];
  }

  String _from(LinkInfo l) => l.driver.startsWith('pkg:')
      ? S.current.packageNamed(l.driver.substring(4))
      : S.current.builtInDriver(l.driver);

  String _modeLabel(LinkInfo l) {
    final pkg = l.driver.startsWith('pkg:')
        ? packages.table[l.driver.substring(4)]
        : null;
    if (pkg?.kind == 'wasm') {
      return 'WASM';
    }
    return switch (l.mode) {
      LinkMode.embedded => S.current.modeEmbedded,
      LinkMode.process => S.current.modeProcess,
      LinkMode.wasm => 'WASM',
      LinkMode.external => S.current.modeExternal,
    };
  }

  (Tone, String) _stateWord(String s) => switch (s) {
    'connected' => (Tone.good, S.current.stateConnected),
    'starting' => (Tone.warn, S.current.stateStarting),
    'stopping' => (Tone.warn, S.current.stateStopping),
    'stopped' => (Tone.neutral, S.current.stateStopped),
    'failed' => (Tone.bad, S.current.stateFailed),
    _ => (Tone.neutral, S.current.stateInstalled),
  };

  RowVm _localRow(LinkInfo l) {
    final pkg = l.driver.startsWith('pkg:')
        ? packages.table[l.driver.substring(4)]
        : null;
    final (tone, word) = _stateWord(_state(l));
    return RowVm(
      id: l.id,
      selected: links.selectedLink == l.id,
      cells: [
        CellVm(title: l.id, subtitle: _from(l), strong: true),
        if (pkg != null)
          CellVm(
            title: '${pkg.version} · ${_sourceWord(pkg.source)}',
            subtitle: pkg.sha256 == null
                ? null
                : 'sha256 ${_short(pkg.sha256!)}',
          )
        else
          CellVm(
            title: 'wyrmd ${links.version ?? ''}'.trim(),
            subtitle: 'downstream/${l.id}',
          ),
        CellVm(chip: _modeLabel(l)),
        CellVm(title: word, tone: tone, mark: tone == Tone.warn ? .ring : .dot),
      ],
    );
  }

  RowVm _updateRow(LinkInfo l) {
    final p = _pkg(_packageOf(l))!;
    final official = _isOfficial(p);
    final checking = p.lastUpdate?.result == 'checking';
    final peers = _linksOf(p.name);
    return RowVm(
      id: l.id,
      selected: updates.package == p.name,
      cells: [
        CellVm(title: l.id, subtitle: _modeLabel(l), strong: true),
        CellVm(
          title: S.current.packageNamed(p.name),
          subtitle: official ? S.current.updOfficial : S.current.updCustom,
        ),
        CellVm(
          title: official ? '${p.version} → ${p.latest}' : p.version,
          monospace: true,
          tone: official ? Tone.ember : null,
          mark: .none,
        ),
        CellVm(
          title: checking
              ? S.current.updRowChecking
              : (official
                    ? (peers.length > 1 ? S.current.updTogether : '')
                    : S.current.updFromFileRow),
          tone: checking ? Tone.warn : (official ? null : Tone.ember),
          mark: checking ? .ring : .none,
        ),
      ],
    );
  }

  RowVm _remoteRow(LinkInfo l) {
    final s = _state(l);
    final on = s == 'connected';
    return RowVm(
      id: l.id,
      selected: links.selectedLink == l.id,
      cells: [
        CellVm(title: l.id, subtitle: l.device ?? l.note, strong: true),
        CellVm(
          title: 'CN ${l.certificateCn ?? l.id} · ${site.viewed} CA',
          subtitle: _from(l),
        ),
        CellVm(chip: S.current.modeExternal),
        CellVm(
          title: on ? S.current.stateConnected : S.current.stateOffline,
          tone: on ? Tone.good : Tone.neutral,
          subtitle: on ? null : _stateWord(s).$2,
        ),
      ],
    );
  }

  RowVm _quarantineRow(QuarantineEntry q) {
    final broker = q.kind == 'broker';
    return RowVm(
      id: q.node,
      selected: quarantine.selectedEntry == q.node,
      cells: [
        CellVm(
          title: q.cn,
          subtitle: broker
              ? S.current.downstreamBrokerQuic
              : S.current.linkOverTls,
          strong: true,
        ),
        CellVm(
          title: q.from == null ? '—' : S.current.fromAddress(q.from!),
          subtitle: q.via.isEmpty
              ? S.current.caSigned(site.viewed ?? '')
              : S.current.asksToRelay(q.via.join(', ')),
        ),
        CellVm(
          chip: broker
              ? S.current.whyBroker
              : (q.deauthorized ? S.current.whyDeauthorized : S.current.whyNew),
        ),
        CellVm(
          title: S.current.stateWaiting,
          tone: Tone.warn,
          subtitle: broker
              ? S.current.decideInSites
              : (q.firstSeen == null
                    ? null
                    : S.current.firstSeen(_ago(q.firstSeen!))),
        ),
      ],
    );
  }

  DetailInspectorVm? _inspector(LinksTab tab) {
    if (tab == LinksTab.quarantine) {
      final sel = quarantine.selectedEntry;
      final q = sel == null ? null : quarantine.table[sel];
      return q == null ? null : _quarantineInspector(q);
    }
    if (tab == LinksTab.updates) {
      // A row of Updates opens the update sheet, not the inspector.
      return null;
    }
    final sel = links.selectedLink;
    final l = sel == null ? null : links.table[sel];
    if (l == null || _external(l) != (tab == LinksTab.remote)) {
      return null;
    }
    return _external(l) ? _remoteInspector(l) : _localInspector(l);
  }

  DetailInspectorVm _localInspector(LinkInfo l) {
    final key = '$_root/sys/links/${l.id}';
    final reason = site.needs('config', key);
    final state = _state(l);
    final (tone, word) = _stateWord(state);
    final running = state == 'connected' || state == 'starting';
    final pkg = _pkg(_packageOf(l));
    final points = _points(l.id);
    ActionRowVm row(
      String id,
      String icon,
      String title,
      String desc,
      String code, {
      Tone tone = Tone.neutral,
      String? off,
    }) => ActionRowVm(
      id: id,
      icon: icon,
      title: title,
      description: desc,
      code: code,
      tone: tone,
      disabledReason: off == '' ? null : off ?? reason,
    );
    return DetailInspectorVm(
      eyebrow: S.current.runsOn(site.viewed ?? ''),
      title: l.id,
      pill: StatusPillVm(
        label: word,
        tone: tone,
        mark: tone == Tone.warn ? .ring : .dot,
      ),
      keyName: 'sys/links/${l.id}',
      facts: [
        FactVm(label: S.current.factFrom, value: _from(l)),
        FactVm(
          label: S.current.factVersion,
          value: pkg == null ? 'wyrmd ${links.version ?? ''}' : pkg.version,
        ),
        FactVm(label: S.current.factRunsAs, value: _modeLabel(l)),
        FactVm(
          label: S.current.factBranch,
          value: '$_root/downstream/${l.id}',
          mono: true,
        ),
        if (points.isNotEmpty)
          FactVm(
            label: S.current.factRestorePoints,
            value: '${points.length}',
          ),
      ],
      groups: [
        ActionGroupVm(
          label: S.current.groupRun,
          actions: [
            if (running)
              row(
                'stop',
                'action_stop',
                S.current.actStop,
                S.current.actStopNote,
                'stop',
              )
            else
              row(
                'start',
                'action_play',
                S.current.actStart,
                S.current.actStartNote,
                'start',
              ),
            row(
              'log',
              'action_log',
              S.current.actViewLog,
              S.current.actViewLogNote,
              'get_log',
            ),
          ],
        ),
        ActionGroupVm(
          label: S.current.groupChange,
          actions: [
            row(
              'params',
              'action_edit',
              S.current.actEditParams,
              S.current.actEditParamsNote,
              'update',
            ),
            row(
              'history',
              'action_hist',
              S.current.actParamsHistory,
              S.current.actParamsHistoryNote,
              'history · rollback',
            ),
            row(
              'secrets',
              'action_key',
              S.current.actSecrets,
              S.current.actSecretsNote,
              'set_secret',
            ),
            row(
              'grant',
              'action_grant',
              S.current.actGrant,
              S.current.actGrantNote,
              'grant',
            ),
          ],
        ),
        ActionGroupVm(
          label: S.current.groupVersion,
          actions: [
            if (pkg == null)
              ActionRowVm(
                id: 'builtin',
                icon: 'action_lock',
                title: S.current.actComesWithWyrmd,
                description: S.current.actComesWithWyrmdNote,
                disabledReason: S.current.actComesWithWyrmdNote,
              )
            else ...[
              if (pkg.updateAvailable)
                row(
                  'update',
                  'action_up',
                  S.current.actUpdateTo(pkg.latest),
                  S.current.actUpdateToNote,
                  'update',
                  tone: Tone.ember,
                )
              else if (!_isOfficial(pkg))
                row(
                  'update',
                  'action_up',
                  S.current.actUpdateFromFile,
                  S.current.actUpdateFromFileNote,
                  'install_zip',
                ),
              if (pkg.lastUpdate != null || points.isNotEmpty)
                row(
                  'versions',
                  'action_hist',
                  S.current.actVersions,
                  S.current.actVersionsNote,
                  'rollback',
                  // Reading it needs no right; Roll back inside does.
                  off: '',
                ),
            ],
          ],
        ),
        ActionGroupVm(
          label: S.current.groupRemove,
          actions: [
            row(
              'remove',
              'action_trash',
              S.current.actRemoveLink,
              S.current.actRemoveLinkNote,
              'remove',
              tone: Tone.bad,
            ),
          ],
        ),
      ],
    );
  }

  DetailInspectorVm _remoteInspector(LinkInfo l) {
    final key = '$_root/sys/links/${l.id}';
    final reason = site.needs('config', key);
    final on = _state(l) == 'connected';
    return DetailInspectorVm(
      eyebrow: S.current.runsOnAnotherDevice,
      title: l.id,
      pill: on
          ? StatusPillVm(label: S.current.stateConnected, tone: Tone.good)
          : StatusPillVm(label: S.current.stateOffline, tone: Tone.neutral),
      keyName: 'sys/links/${l.id}',
      facts: [
        if (l.device case final d?)
          FactVm(label: S.current.factDevice, value: d, mono: true),
        FactVm(
          label: S.current.factCertificate,
          value: 'CN ${l.certificateCn ?? l.id} · ${site.viewed} CA',
        ),
        FactVm(
          label: S.current.factBranch,
          value: '$_root/downstream/${l.id}',
          mono: true,
        ),
      ],
      groups: [
        ActionGroupVm(
          label: S.current.groupYouControl,
          actions: [
            ActionRowVm(
              id: 'grant',
              icon: 'action_grant',
              title: S.current.actGrants,
              description: S.current.actGrantsNote,
              code: 'grant',
              disabledReason: reason,
            ),
            ActionRowVm(
              id: 'deauthorize',
              icon: 'action_block',
              title: S.current.actDeauthorize,
              description: S.current.actDeauthorizeNote,
              code: 'deauthorize',
              tone: Tone.warn,
              disabledReason: reason,
            ),
            ActionRowVm(
              id: 'remove',
              icon: 'action_trash',
              title: S.current.actRemoveForGood,
              description: S.current.actRemoveForGoodNote,
              code: 'remove',
              tone: Tone.bad,
              disabledReason: reason,
            ),
          ],
        ),
        ActionGroupVm(
          label: S.current.groupOnTheDevice,
          actions: [
            ActionRowVm(
              id: 'device-run',
              icon: 'action_play',
              title: S.current.actStartStopRestart,
              disabledReason: S.current.doneOnTheDevice(l.device ?? l.id),
            ),
            ActionRowVm(
              id: 'device-upgrade',
              icon: 'action_up',
              title: S.current.actUpgradeParamsLog,
              disabledReason: S.current.doneOnTheDeviceUpgrade,
            ),
          ],
        ),
      ],
      footer: S.current.remoteFooter,
    );
  }

  DetailInspectorVm _quarantineInspector(QuarantineEntry q) {
    final key = '$_root/sys/quarantine/${q.node}';
    final reason = site.needs('config', key);
    final broker = q.kind == 'broker';
    final specs = quarantine.forms[q.node];
    return DetailInspectorVm(
      eyebrow: S.current.waitingInQuarantine,
      title: q.cn,
      pill: StatusPillVm(
        label: S.current.stateWaiting,
        tone: Tone.warn,
        mark: .ring,
      ),
      keyName: 'sys/quarantine/${q.node}',
      facts: [
        if (q.from case final f?)
          FactVm(label: S.current.factFrom, value: S.current.fromAddress(f)),
        FactVm(
          label: S.current.factKind,
          value: broker
              ? S.current.downstreamBrokerQuic
              : S.current.linkOverTls,
        ),
        if (q.firstSeen case final t?)
          FactVm(
            label: S.current.factSeen,
            value: S.current.firstSeen(_ago(t)),
          ),
        if (q.via.isNotEmpty)
          FactVm(
            label: S.current.factRelays,
            value: q.via.join(', '),
            mono: true,
          ),
        if (q.key case final k?)
          FactVm(label: S.current.factKey, value: _short(k), mono: true),
        FactVm(label: S.current.factCanDo, value: S.current.canDoNothing),
      ],
      form: specs == null
          ? null
          : InspectorFormVm(
              id: q.node,
              label: broker ? S.current.letTheBrokerIn : S.current.letItIn,
              fields: paramFields(specs),
              submit: S.current.approve,
              secondary: S.current.reject,
              note: broker
                  ? S.current.approveBrokerNote
                  : S.current.approveLinkNote,
              disabledReason: reason,
            ),
    );
  }

  Future<void> _onAction(BuildContext context, String a) async {
    final id = links.selectedLink;
    final node = quarantine.selectedEntry;
    switch (a) {
      case 'start' when id != null:
        await dispatchAndWait(StartLinkAction(id));
      case 'stop' when id != null:
        await dispatchAndWait(StopLinkAction(id));
      case 'log' when id != null:
        await showLinkLog(context, id);
      case 'params' when id != null:
        await showLinkParams(context, id);
      case 'history' when id != null:
        await showLinkHistory(context, id);
      case 'secrets' when id != null:
        await showLinkSecrets(context, '$_root/sys/links/$id');
      case 'grant' when id != null:
        await showLinkGrant(context, id, _root);
      case 'update' when id != null:
        if (_packageOf(links.table[id]!) case final name?) {
          dispatchSync(OpenUpdateAction(name));
        }
      case 'versions' when id != null:
        if (_packageOf(links.table[id]!) case final name?) {
          dispatchSync(OpenUpdateAction(name, follow: true));
        }
      case 'update-all':
        final names = _updatable;
        if (names.isNotEmpty) {
          dispatchSync(
            OpenUpdateAction(names.first, queue: names.sublist(1)),
          );
        }
      case 'sheet-close':
        dispatchSync(CloseUpdateAction());
      case 'sheet-rollback':
        await _rollBack(context);
      case 'sheet-secondary':
        if (_sheetData?.stage == UpdateStage.progress) {
          await _rollBack(context);
        } else {
          dispatchSync(CloseUpdateAction());
        }
      case 'sheet-primary':
        final d = _sheetData;
        switch (d == null ? '' : updatePrimary(d)) {
          case 'update':
            await dispatchAndWait(UpdatePackageAction());
          case 'file':
            final f = await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: ['zip'],
            );
            if (f != null) {
              await dispatchAndWait(
                UpdatePackageAction(zip: await f.readAsBytes()),
              );
            }
          case 'rollback':
            await _rollBack(context);
          case 'log' when d!.links.isNotEmpty:
            await showLinkLog(context, d.links.first);
          case 'open' when d!.links.isNotEmpty:
            dispatchSync(CloseUpdateAction());
            dispatchSync(SetTabAction(LinksTab.local));
            dispatchSync(SetSelectedLinkAction(d.links.first));
        }
      case 'remove' when id != null:
        final external = links.table[id]?.mode == LinkMode.external;
        if (await ConfirmDialog.ask(
          context,
          title: S.current.removeLinkTitle(id),
          message: external || links.table[id]?.mode == LinkMode.process
              ? S.current.removeRetiresId
              : S.current.removeDeletesTree,
          confirm: S.current.remove,
          cancel: S.current.cancel,
        )) {
          await dispatchAndWait(RemoveLinkAction(id));
        }
      case 'deauthorize' when id != null:
        if (await ConfirmDialog.ask(
          context,
          title: S.current.deauthorizeTitle(id),
          message: S.current.actDeauthorizeNote,
          confirm: S.current.actDeauthorize,
          cancel: S.current.cancel,
        )) {
          await dispatchAndWait(DeauthorizeLinkAction(id));
        }
      case 'reject' when node != null:
        if (await ConfirmDialog.ask(
          context,
          title: S.current.rejectTitle(quarantine.table[node]?.cn ?? node),
          message: S.current.rejectNote,
          confirm: S.current.reject,
          cancel: S.current.cancel,
        )) {
          await dispatchAndWait(RejectQuarantineAction(node));
        }
    }
  }

  /// *Roll back to `<v>`…*: the confirm names the links that restart.
  Future<void> _rollBack(BuildContext context) async {
    final d = _sheetData;
    final to = d?.package.previous;
    if (d == null || to == null) {
      return;
    }
    if (await ConfirmDialog.ask(
      context,
      title: S.current.updRollBackTitle(d.package.name, to),
      message: S.current.updRollBackNote(to, d.links.join(', ')),
      confirm: S.current.updRollBack,
      cancel: S.current.cancel,
    )) {
      await dispatchAndWait(RollbackPackageAction(d.package.name));
    }
  }

  static String _short(String hash) => hash.length <= 12
      ? hash
      : '${hash.substring(0, 4)}…${hash.substring(hash.length - 4)}';

  static String _sourceWord(String? source) => (source ?? '').split(' ').first;

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inMinutes < 1) {
      return S.current.agoNow;
    }
    if (d.inHours < 1) {
      return S.current.agoMinutes(d.inMinutes);
    }
    if (d.inDays < 1) {
      return S.current.agoHours(d.inHours);
    }
    return S.current.agoDays(d.inDays);
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.addReason,
    required this.tab,
    required this.tabs,
    required this.description,
    required this.settings,
    required this.columns,
    required this.rows,
    required this.empty,
    required this.inspector,
    required this.updateAll,
    required this.sheet,
    required this.onSheetToggle,
    required this.busy,
    required this.onShow,
    required this.onHide,
    required this.onTapLinkInstall,
    required this.onTab,
    required this.onRow,
    required this.onAction,
    required this.onSubmit,
  }) : super(
         equals: [
           site,
           addReason,
           tab,
           tabs,
           description,
           settings,
           columns,
           rows,
           empty,
           inspector,
           updateAll,
           sheet,
           busy,
         ],
       );

  final String site;
  final String? addReason;
  final String tab;
  final List<TabItemVm> tabs;
  final String description;
  final List<SettingCardVm> settings;
  final List<ColumnVm> columns;
  final List<RowVm> rows;
  final String? empty;
  final DetailInspectorVm? inspector;

  /// `Update all official…` is offered.
  final bool updateAll;

  /// The update of a package, as a drawer.
  final TaskSheetVm? sheet;
  final void Function(String id, {required bool value}) onSheetToggle;
  final bool busy;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onTapLinkInstall;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onRow;
  final Future<void> Function(BuildContext context, String action) onAction;
  final FutureOr<FieldRefusal?> Function(Map<String, Object?> values) onSubmit;
}
