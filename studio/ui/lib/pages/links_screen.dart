import 'dart:async';

import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/detail_inspector.dart';
import '../containers/fact_grid.dart';
import '../indicators/status_pill.dart';
import '../models/link_run_mode.dart';
import '../models/submit.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../overlays/confirm_dialog.dart';
import '../overlays/link_update_sheet.dart';
import '../tables/row_table.dart';
import 'links_data.dart';
import 'links_page.dart';

export 'links_data.dart';

/// Links (boards *Studio · Links*, *Links · On other devices*, *Links ·
/// Quarantine*, `LinkUpdate*`) from typed values: it words them in the
/// language on screen and draws them with [LinksPage]. Remove, Deauthorize,
/// Reject and every rollback ask first, here; the rest reports to its
/// callback.
class LinksScreen extends StatelessWidget {
  const LinksScreen({
    required this.vm,
    required this.onAdd,
    required this.onTab,
    required this.onRow,
    required this.onAct,
    required this.onDialog,
    required this.onRemove,
    required this.onDeauthorize,
    required this.onReject,
    required this.approve,
    required this.onHoldUnknown,
    required this.onAllowAll,
    required this.onUpdateAll,
    required this.onTakePoint,
    required this.onAutoRollback,
    required this.onAcceptNew,
    required this.onUpdate,
    required this.onUpdateFromFile,
    required this.onRollBack,
    required this.onShowLink,
    required this.onCloseSheet,
    super.key,
  });

  final LinksScreenVm vm;
  final VoidCallback onAdd;
  final ValueChanged<LinksTabKey> onTab;
  final ValueChanged<String> onRow;

  /// An action card of the selected link that runs at once (Start, Stop,
  /// Update to…, Update from file…, Versions…).
  final ValueChanged<LinkAct> onAct;

  /// A dialog of a link (its log, params, history, secrets, grants, a
  /// backup).
  final ValueChanged<LinkDialogAsk> onDialog;

  /// A link to remove, to deauthorize, a connection to reject, once the
  /// user said yes.
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onDeauthorize;
  final ValueChanged<String> onReject;

  /// The form of a connection's Approve.
  final SubmitVm approve;
  final ValueChanged<bool> onHoldUnknown;
  final ValueChanged<bool> onAllowAll;
  final VoidCallback onUpdateAll;

  /// The options of the update review.
  final ValueChanged<bool> onTakePoint;
  final ValueChanged<bool> onAutoRollback;
  final ValueChanged<bool> onAcceptNew;

  /// The update sheet's package: update it, from a file, roll the package
  /// [onRollBack] names back (once the user said yes); the link
  /// [onShowLink] names on this broker; the sheet closed.
  final VoidCallback onUpdate;
  final VoidCallback onUpdateFromFile;
  final ValueChanged<String> onRollBack;
  final ValueChanged<String> onShowLink;
  final VoidCallback onCloseSheet;

  @override
  Widget build(BuildContext context) {
    final sheet = vm.sheet;
    return LinksPage(
      title: S.current.linksOn(vm.site),
      subtitle: S.current.linksSubtitle,
      addLabel: S.current.addALink,
      onTapLinkInstall: vm.addReason == null ? onAdd : null,
      addReason: vm.addReason,
      tabs: [
        for (final t in vm.tabs)
          TabItemVm(
            id: t.tab,
            label: t.tab.label,
            count: '${t.count}',
            countTone: switch (t.tab) {
              LinksTabKey.updates => Tone.ember,
              LinksTabKey.quarantine when t.count > 0 => Tone.warn,
              LinksTabKey.local ||
              LinksTabKey.remote ||
              LinksTabKey.quarantine => Tone.neutral,
            },
          ),
      ],
      tab: vm.tab,
      description: switch (vm.tab) {
        LinksTabKey.local => S.current.linksLocalNote(vm.site),
        LinksTabKey.updates => S.current.updTabNote,
        LinksTabKey.remote => S.current.linksRemoteNote,
        LinksTabKey.quarantine => S.current.linksQuarantineNote,
      },
      settings: vm.tab == LinksTabKey.quarantine ? _settings() : const [],
      columns: _columns(),
      rows: switch (vm.tab) {
        LinksTabKey.local => [for (final l in vm.local) _localRow(l)],
        LinksTabKey.updates => [for (final l in vm.toUpdate) _updateRow(l)],
        LinksTabKey.remote => [for (final l in vm.remote) _remoteRow(l)],
        LinksTabKey.quarantine => [
          for (final q in vm.waiting) _quarantineRow(q),
        ],
      },
      empty: switch (vm.tab) {
        _ when vm.loading => S.current.loading,
        LinksTabKey.local => S.current.noLocalLinks,
        LinksTabKey.updates => S.current.updNothing,
        LinksTabKey.remote => S.current.noRemoteLinks,
        LinksTabKey.quarantine => S.current.nothingInQuarantine,
      },
      inspector: _inspector(),
      busy: vm.busy,
      onTab: onTab,
      onRow: onRow,
      onAction: (a) => _act(context, a),
      onSubmit: approve.onSubmit,
      onSecondary: () => unawaited(_reject(context)),
      secondLabel: vm.updateAll ? S.current.updAllOfficial : null,
      secondReason: vm.addReason,
      onSecond: onUpdateAll,
      sheet: sheet == null
          ? null
          : linkUpdateSheet(
              sheet,
              onTakePoint: onTakePoint,
              onAutoRollback: onAutoRollback,
              onAcceptNew: onAcceptNew,
              onRollBack: () => unawaited(_rollBack(context)),
            ),
      onSheetPrimary: () => _primary(context),
      onSheetSecondary: () => _secondary(context),
      onSheetClose: onCloseSheet,
    );
  }

  // ---- the words of the typed values -------------------------------------

  List<SettingCardVm> _settings() => [
    SettingCardVm(
      title: S.current.holdUnknown,
      description: S.current.holdUnknownNote,
      keyName: 'sys/enable_quarantine',
      disabledReason: vm.admissionReason,
      value: FieldVm(
        value: vm.holdUnknown,
        enabled: vm.admissionReason == null,
        onChanged: onHoldUnknown,
      ),
    ),
    SettingCardVm(
      title: S.current.allowAllLinks,
      description: S.current.allowAllLinksNote,
      keyName: 'sys/allow_all_links',
      disabledReason: vm.admissionReason,
      value: FieldVm(
        value: vm.allowAll,
        enabled: vm.admissionReason == null,
        onChanged: onAllowAll,
      ),
    ),
  ];

  List<ColumnVm> _columns() => switch (vm.tab) {
    LinksTabKey.local => [
      ColumnVm(S.current.colLink, flex: 3),
      ColumnVm(S.current.colVersionSource, flex: 3),
      ColumnVm(S.current.colRunsAs, flex: 2),
      ColumnVm(S.current.colState, flex: 3),
    ],
    LinksTabKey.updates => [
      ColumnVm(S.current.colLink, flex: 3),
      ColumnVm(S.current.updColPackage, flex: 3),
      ColumnVm(S.current.updColVersion, flex: 2),
      ColumnVm(S.current.colState, flex: 3),
    ],
    LinksTabKey.remote => [
      ColumnVm(S.current.colLinkDevice, flex: 3),
      ColumnVm(S.current.colCertificate, flex: 3),
      ColumnVm(S.current.colMode, flex: 2),
      ColumnVm(S.current.colState, flex: 3),
    ],
    LinksTabKey.quarantine => [
      ColumnVm(S.current.colWho, flex: 3),
      ColumnVm(S.current.colFrom, flex: 3),
      ColumnVm(S.current.colWhyHere, flex: 2),
      ColumnVm(S.current.colState, flex: 3),
    ],
  };

  /// Where a link comes from: its package or its built-in driver.
  static String _from(LinkData l) => switch (l.package) {
    final p? => S.current.packageNamed(p.name),
    null => S.current.builtInDriver(l.driver),
  };

  static String _short(String hash) => hash.length <= 12
      ? hash
      : '${hash.substring(0, 4)}…${hash.substring(hash.length - 4)}';

  static String _sourceWord(String? source) => (source ?? '').split(' ').first;

  String get _wyrmd => 'wyrmd ${vm.brokerVersion ?? ''}';

  String _certificate(LinkData l) =>
      'CN ${l.certificateCn ?? l.id} · ${vm.site} CA';

  RowVm<String> _localRow(LinkData l) {
    final pkg = l.package;
    final s = l.state;
    return RowVm(
      id: l.id,
      selected: vm.selectedLink == l.id,
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
          CellVm(title: _wyrmd.trim(), subtitle: 'downstream/${l.id}'),
        CellVm(chip: l.runsAs.label),
        CellVm(
          title: s.label,
          tone: s.tone,
          mark: s.tone == Tone.warn ? .ring : .dot,
        ),
      ],
    );
  }

  RowVm<String> _updateRow(LinkData l) {
    final p = l.package!;
    return RowVm(
      id: l.id,
      selected: vm.updating == p.name,
      cells: [
        CellVm(title: l.id, subtitle: l.runsAs.label, strong: true),
        CellVm(
          title: S.current.packageNamed(p.name),
          subtitle: p.official ? S.current.updOfficial : S.current.updCustom,
        ),
        CellVm(
          title: p.official ? '${p.version} → ${p.latest}' : p.version,
          monospace: true,
          tone: p.official ? Tone.ember : null,
          mark: .none,
        ),
        CellVm(
          title: p.checking
              ? S.current.updRowChecking
              : (p.official
                    ? (p.peers > 1 ? S.current.updTogether : '')
                    : S.current.updFromFileRow),
          tone: p.checking ? Tone.warn : (p.official ? null : Tone.ember),
          mark: p.checking ? .ring : .none,
        ),
      ],
    );
  }

  RowVm<String> _remoteRow(LinkData l) {
    final on = l.state == LinkStateWord.connected;
    return RowVm(
      id: l.id,
      selected: vm.selectedLink == l.id,
      cells: [
        CellVm(title: l.id, subtitle: l.device ?? l.note, strong: true),
        CellVm(title: _certificate(l), subtitle: _from(l)),
        CellVm(chip: S.current.modeExternal),
        CellVm(
          title: on ? S.current.stateConnected : S.current.stateOffline,
          tone: on ? Tone.good : Tone.neutral,
          subtitle: on ? null : l.state.label,
        ),
      ],
    );
  }

  String _kind(QuarantineData q) =>
      q.broker ? S.current.downstreamBrokerQuic : S.current.linkOverTls;

  String _seen(DateTime t) => S.current.firstSeen(Formats.ago(t));

  RowVm<String> _quarantineRow(QuarantineData q) => RowVm(
    id: q.node,
    selected: vm.selectedEntry == q.node,
    cells: [
      CellVm(title: q.cn, subtitle: _kind(q), strong: true),
      CellVm(
        title: q.from == null ? '—' : S.current.fromAddress(q.from!),
        subtitle: q.via.isEmpty
            ? S.current.caSigned(vm.site)
            : S.current.asksToRelay(q.via.join(', ')),
      ),
      CellVm(
        chip: q.broker
            ? S.current.whyBroker
            : (q.deauthorized ? S.current.whyDeauthorized : S.current.whyNew),
      ),
      CellVm(
        title: S.current.stateWaiting,
        tone: Tone.warn,
        subtitle: q.broker
            ? S.current.decideInSites
            : (q.firstSeen == null ? null : _seen(q.firstSeen!)),
      ),
    ],
  );

  LinkData? _link(String? id, List<LinkData> links) =>
      links.where((l) => l.id == id).firstOrNull;

  QuarantineData? get _entry =>
      vm.waiting.where((q) => q.node == vm.selectedEntry).firstOrNull;

  DetailInspectorVm<LinkAct>? _inspector() => switch (vm.tab) {
    LinksTabKey.quarantine => switch (_entry) {
      final q? => _quarantineInspector(q),
      null => null,
    },
    // A row of Updates opens the update sheet, not the inspector.
    LinksTabKey.updates => null,
    LinksTabKey.local => switch (_link(vm.selectedLink, vm.local)) {
      final l? => _localInspector(l),
      null => null,
    },
    LinksTabKey.remote => switch (_link(vm.selectedLink, vm.remote)) {
      final l? => _remoteInspector(l),
      null => null,
    },
  };

  ActionRowVm<LinkAct> _row(
    LinkAct a,
    String title,
    String description, {
    required String? reason,
    Tone tone = Tone.neutral,
  }) => ActionRowVm(
    id: a,
    icon: a.icon,
    title: title,
    description: description,
    code: a.code,
    tone: tone,
    disabledReason: reason,
  );

  DetailInspectorVm<LinkAct> _localInspector(LinkData l) {
    final s = S.current;
    final reason = l.reason;
    final running =
        l.state == LinkStateWord.connected || l.state == LinkStateWord.starting;
    final pkg = l.package;
    return DetailInspectorVm(
      eyebrow: s.runsOn(vm.site),
      title: l.id,
      pill: StatusPillVm(
        label: l.state.label,
        tone: l.state.tone,
        mark: l.state.tone == Tone.warn ? .ring : .dot,
      ),
      keyName: 'sys/links/${l.id}',
      facts: [
        FactVm(label: s.factFrom, value: _from(l)),
        FactVm(label: s.factVersion, value: pkg?.version ?? _wyrmd),
        FactVm(label: s.factRunsAs, value: l.runsAs.label),
        FactVm(
          label: s.factBranch,
          value: '${vm.root}/downstream/${l.id}',
          mono: true,
        ),
        if (l.restorePoints > 0)
          FactVm(label: s.factRestorePoints, value: '${l.restorePoints}'),
      ],
      groups: [
        ActionGroupVm(
          label: s.groupRun,
          actions: [
            if (running)
              _row(LinkAct.stop, s.actStop, s.actStopNote, reason: reason)
            else
              _row(LinkAct.start, s.actStart, s.actStartNote, reason: reason),
            _row(LinkAct.log, s.actViewLog, s.actViewLogNote, reason: reason),
          ],
        ),
        ActionGroupVm(
          label: s.groupChange,
          actions: [
            _row(
              LinkAct.params,
              s.actEditParams,
              s.actEditParamsNote,
              reason: reason,
            ),
            _row(
              LinkAct.history,
              s.actParamsHistory,
              s.actParamsHistoryNote,
              reason: reason,
            ),
            _row(
              LinkAct.secrets,
              s.actSecrets,
              s.actSecretsNote,
              reason: reason,
            ),
            _row(LinkAct.grant, s.actGrant, s.actGrantNote, reason: reason),
          ],
        ),
        ActionGroupVm(
          label: s.groupVersion,
          actions: [
            if (pkg == null)
              ActionRowVm(
                id: LinkAct.builtIn,
                icon: LinkAct.builtIn.icon,
                title: s.actComesWithWyrmd,
                description: s.actComesWithWyrmdNote,
                disabledReason: s.actComesWithWyrmdNote,
              )
            else ...[
              if (pkg.updateAvailable)
                _row(
                  LinkAct.updateTo,
                  s.actUpdateTo(pkg.latest),
                  s.actUpdateToNote,
                  reason: reason,
                  tone: Tone.ember,
                )
              else if (!pkg.official)
                _row(
                  LinkAct.updateFromFile,
                  s.actUpdateFromFile,
                  s.actUpdateFromFileNote,
                  reason: reason,
                ),
              if (pkg.versions || l.restorePoints > 0)
                // Reading it needs no right; Roll back inside does.
                _row(
                  LinkAct.versions,
                  s.actVersions,
                  s.actVersionsNote,
                  reason: null,
                ),
            ],
          ],
        ),
        ActionGroupVm(
          label: s.groupBackup,
          actions: [
            _row(
              LinkAct.backup,
              s.actBackUp,
              s.actBackUpNote,
              // A wyrmd before ADR 0048 has no `sys/backups`.
              reason: reason ?? (vm.hasBackups ? null : s.bakNoBackups),
            ),
          ],
        ),
        ActionGroupVm(
          label: s.groupRemove,
          actions: [
            _row(
              LinkAct.remove,
              s.actRemoveLink,
              s.actRemoveLinkNote,
              reason: reason,
              tone: Tone.bad,
            ),
          ],
        ),
      ],
    );
  }

  DetailInspectorVm<LinkAct> _remoteInspector(LinkData l) {
    final s = S.current;
    final reason = l.reason;
    final on = l.state == LinkStateWord.connected;
    return DetailInspectorVm(
      eyebrow: s.runsOnAnotherDevice,
      title: l.id,
      pill: on
          ? StatusPillVm(label: s.stateConnected, tone: Tone.good)
          : StatusPillVm(label: s.stateOffline, tone: Tone.neutral),
      keyName: 'sys/links/${l.id}',
      facts: [
        if (l.device case final d?)
          FactVm(label: s.factDevice, value: d, mono: true),
        FactVm(label: s.factCertificate, value: _certificate(l)),
        FactVm(
          label: s.factBranch,
          value: '${vm.root}/downstream/${l.id}',
          mono: true,
        ),
      ],
      groups: [
        ActionGroupVm(
          label: s.groupYouControl,
          actions: [
            _row(LinkAct.grants, s.actGrants, s.actGrantsNote, reason: reason),
            _row(
              LinkAct.deauthorize,
              s.actDeauthorize,
              s.actDeauthorizeNote,
              reason: reason,
              tone: Tone.warn,
            ),
            _row(
              LinkAct.removeForGood,
              s.actRemoveForGood,
              s.actRemoveForGoodNote,
              reason: reason,
              tone: Tone.bad,
            ),
          ],
        ),
        ActionGroupVm(
          label: s.groupOnTheDevice,
          actions: [
            ActionRowVm(
              id: LinkAct.deviceRun,
              icon: LinkAct.deviceRun.icon,
              title: s.actStartStopRestart,
              disabledReason: s.doneOnTheDevice(l.device ?? l.id),
            ),
            ActionRowVm(
              id: LinkAct.deviceUpgrade,
              icon: LinkAct.deviceUpgrade.icon,
              title: s.actUpgradeParamsLog,
              disabledReason: s.doneOnTheDeviceUpgrade,
            ),
          ],
        ),
      ],
      footer: s.remoteFooter,
    );
  }

  DetailInspectorVm<LinkAct> _quarantineInspector(QuarantineData q) {
    final s = S.current;
    final fields = q.fields;
    return DetailInspectorVm(
      eyebrow: s.waitingInQuarantine,
      title: q.cn,
      pill: StatusPillVm(label: s.stateWaiting, tone: Tone.warn, mark: .ring),
      keyName: 'sys/quarantine/${q.node}',
      facts: [
        if (q.from case final f?)
          FactVm(label: s.factFrom, value: s.fromAddress(f)),
        FactVm(label: s.factKind, value: _kind(q)),
        if (q.firstSeen case final t?)
          FactVm(label: s.factSeen, value: _seen(t)),
        if (q.via.isNotEmpty)
          FactVm(label: s.factRelays, value: q.via.join(', '), mono: true),
        if (q.key case final k?)
          FactVm(label: s.factKey, value: _short(k), mono: true),
        FactVm(label: s.factCanDo, value: s.canDoNothing),
      ],
      form: fields == null
          ? null
          : InspectorFormVm(
              id: q.node,
              label: q.broker ? s.letTheBrokerIn : s.letItIn,
              fields: fields,
              submit: s.approve,
              secondary: s.reject,
              note: q.broker ? s.approveBrokerNote : s.approveLinkNote,
              disabledReason: q.reason,
            ),
    );
  }

  // ---- what the controls do ----------------------------------------------

  LinkData? get _selected =>
      _link(vm.selectedLink, [...vm.local, ...vm.remote]);

  void _act(BuildContext context, LinkAct a) {
    final l = _selected;
    if (l == null) {
      return;
    }
    switch (a) {
      case LinkAct.log:
        onDialog(LinkDialogAsk(LinkDialog.log, l.id));
      case LinkAct.params:
        onDialog(LinkDialogAsk(LinkDialog.params, l.id));
      case LinkAct.history:
        onDialog(LinkDialogAsk(LinkDialog.history, l.id));
      case LinkAct.secrets:
        onDialog(LinkDialogAsk(LinkDialog.secrets, l.id));
      case LinkAct.grant || LinkAct.grants:
        onDialog(LinkDialogAsk(LinkDialog.grant, l.id));
      case LinkAct.backup:
        onDialog(LinkDialogAsk(LinkDialog.backup, l.id));
      case LinkAct.remove || LinkAct.removeForGood:
        unawaited(_remove(context, l));
      case LinkAct.deauthorize:
        unawaited(_deauthorize(context, l));
      case LinkAct.stop ||
          LinkAct.start ||
          LinkAct.updateTo ||
          LinkAct.updateFromFile ||
          LinkAct.versions:
        onAct(a);
      case LinkAct.builtIn || LinkAct.deviceRun || LinkAct.deviceUpgrade:
        break;
    }
  }

  Future<void> _remove(BuildContext context, LinkData l) async {
    if (await ConfirmDialog.ask(
      context,
      title: S.current.removeLinkTitle(l.id),
      message: l.mode == LinkRunMode.external || l.mode == LinkRunMode.process
          ? S.current.removeRetiresId
          : S.current.removeDeletesTree,
      confirm: S.current.remove,
      cancel: S.current.cancel,
    )) {
      onRemove(l.id);
    }
  }

  Future<void> _deauthorize(BuildContext context, LinkData l) async {
    if (await ConfirmDialog.ask(
      context,
      title: S.current.deauthorizeTitle(l.id),
      message: S.current.actDeauthorizeNote,
      confirm: S.current.actDeauthorize,
      cancel: S.current.cancel,
    )) {
      onDeauthorize(l.id);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final q = _entry;
    if (q == null) {
      return;
    }
    if (await ConfirmDialog.ask(
      context,
      title: S.current.rejectTitle(q.cn),
      message: S.current.rejectNote,
      confirm: S.current.reject,
      cancel: S.current.cancel,
    )) {
      onReject(q.node);
    }
  }

  /// *Roll back to `<v>`…*: the confirm names the links that restart.
  Future<void> _rollBack(BuildContext context) async {
    final d = vm.sheet;
    final to = d?.previous;
    if (d == null || to == null) {
      return;
    }
    if (await ConfirmDialog.ask(
      context,
      title: S.current.updRollBackTitle(d.name, to),
      message: S.current.updRollBackNote(to, d.links.join(', ')),
      confirm: S.current.updRollBack,
      cancel: S.current.cancel,
    )) {
      onRollBack(d.name);
    }
  }

  void _primary(BuildContext context) {
    final d = vm.sheet;
    switch (d?.next) {
      case LinkUpdateNext.update:
        onUpdate();
      case LinkUpdateNext.file:
        onUpdateFromFile();
      case LinkUpdateNext.rollback:
        unawaited(_rollBack(context));
      case LinkUpdateNext.log when d!.links.isNotEmpty:
        onDialog(LinkDialogAsk(LinkDialog.log, d.links.first));
      case LinkUpdateNext.open when d!.links.isNotEmpty:
        onShowLink(d.links.first);
      case LinkUpdateNext.log || LinkUpdateNext.open || null:
        break;
    }
  }

  /// The second button: while an update runs and a version is kept, it
  /// rolls back (asked first); else it closes the sheet.
  void _secondary(BuildContext context) {
    final d = vm.sheet;
    if (d?.stage == LinkUpdateStage.progress && d?.previous != null) {
      unawaited(_rollBack(context));
    } else {
      onCloseSheet();
    }
  }
}
