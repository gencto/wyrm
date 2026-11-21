import 'package:business/wyrm/link_update.dart';
import 'package:models/backups_read.dart';
import 'package:models/link_state.dart';
import 'package:models/links_tab.dart';
import 'package:models/package_info.dart';
import 'package:models/package_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/update_next.dart';
import 'package:models/update_report.dart';
import 'package:models/update_result.dart';
import 'package:models/update_stage.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/pages/links_data.dart';

import 'rights_mappers.dart';

// Links: one exhaustive map per domain enum to the `ui` enum that draws
// it, both ways where a control reports a `ui` value back
// (studio-rules §3).

extension LinksTabUi on LinksTab {
  LinksTabKey get ui => switch (this) {
    LinksTab.local => LinksTabKey.local,
    LinksTab.updates => LinksTabKey.updates,
    LinksTab.remote => LinksTabKey.remote,
    LinksTab.quarantine => LinksTabKey.quarantine,
  };
}

extension LinksTabKeyDomain on LinksTabKey {
  LinksTab get domain => switch (this) {
    LinksTabKey.local => LinksTab.local,
    LinksTabKey.updates => LinksTab.updates,
    LinksTabKey.remote => LinksTab.remote,
    LinksTabKey.quarantine => LinksTab.quarantine,
  };
}

extension LinkStateUi on LinkState {
  LinkStateWord get ui => switch (this) {
    LinkState.installed => LinkStateWord.installed,
    LinkState.starting => LinkStateWord.starting,
    LinkState.connected => LinkStateWord.connected,
    LinkState.stopping => LinkStateWord.stopping,
    LinkState.stopped => LinkStateWord.stopped,
    LinkState.failed => LinkStateWord.failed,
  };
}

extension UpdateStageUi on UpdateStage {
  LinkUpdateStage get ui => switch (this) {
    UpdateStage.review => LinkUpdateStage.review,
    UpdateStage.progress => LinkUpdateStage.progress,
    UpdateStage.result => LinkUpdateStage.result,
    UpdateStage.points => LinkUpdateStage.points,
  };
}

extension UpdateResultUi on UpdateResult {
  LinkUpdateEnd get ui => switch (this) {
    UpdateResult.checking => LinkUpdateEnd.checking,
    UpdateResult.ok => LinkUpdateEnd.ok,
    UpdateResult.rolledBack => LinkUpdateEnd.rolledBack,
    UpdateResult.failed => LinkUpdateEnd.failed,
    UpdateResult.unknown => LinkUpdateEnd.unknown,
  };
}

extension UpdateNextUi on UpdateNext {
  LinkUpdateNext get ui => switch (this) {
    UpdateNext.update => LinkUpdateNext.update,
    UpdateNext.file => LinkUpdateNext.file,
    UpdateNext.rollback => LinkUpdateNext.rollback,
    UpdateNext.log => LinkUpdateNext.log,
    UpdateNext.open => LinkUpdateNext.open,
  };
}

/// A moment of the broker's clock, in Unix seconds.
DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

extension UpdateReportUi on UpdateReport {
  LinkUpdateReport get ui => LinkUpdateReport(
    from: from,
    to: to,
    at: _at(at),
    end: result?.ui,
    endWord: resultWord,
    kept: kept,
    added: added,
    gone: gone,
    newKeys: newKeys.unlock,
    goneKeys: goneKeys.unlock,
    reason: reason,
    links: links.unlock,
    restorePoint: restorePoint,
  );
}

extension PackageInfoUi on PackageInfo {
  /// Its words on a link's row and inspector; [peers] links run it,
  /// [restorePoints] of the link are kept.
  LinkPackageData data({required int peers, required int restorePoints}) =>
      LinkPackageData(
        name: name,
        version: version,
        source: source,
        sha256: sha256,
        wasm: kind == PackageKind.wasm,
        latest: latest,
        updateAvailable: updateAvailable,
        versions: lastUpdate != null,
        checking: lastUpdate?.result == UpdateResult.checking,
        peers: peers,
      );
}

extension QuarantineEntryUi on QuarantineEntry {
  /// Its row and inspector; [fields] the form of its `approve`, [reason]
  /// why the user may not decide (neither for an entry that was not
  /// read: no Authorize is offered for it).
  QuarantineData data({List<ParamFieldVm>? fields, Disabled? reason}) =>
      switch (this) {
        QuarantineLink(
          :final node,
          :final cn,
          :final from,
          :final firstSeen,
          :final deauthorized,
        ) =>
          QuarantineLinkData(
            node: node,
            cn: cn,
            from: from,
            firstSeen: firstSeen,
            deauthorized: deauthorized,
            fields: fields,
            reason: reason,
          ),
        QuarantineBroker(
          :final node,
          :final cn,
          :final from,
          :final firstSeen,
          :final via,
          :final key,
        ) =>
          QuarantineBrokerData(
            node: node,
            cn: cn,
            from: from,
            firstSeen: firstSeen,
            via: via.unlock,
            key: key,
            fields: fields,
            reason: reason,
          ),
        QuarantineNotRead(:final node, :final cn) => QuarantineNotReadData(
          node: node,
          cn: cn,
        ),
      };
}

extension LinkUpdateUi on LinkUpdate {
  LinkUpdateData get ui {
    final p = package;
    return LinkUpdateData(
      name: p.name,
      version: p.version,
      stage: stage.ui,
      links: links,
      latest: p.latest,
      official: official,
      wasm: p.kind == PackageKind.wasm,
      title: title,
      summary: summary,
      takePoint: takePoint,
      autoRollback: autoRollback,
      acceptNew: acceptNew,
      changesState: p.changesState,
      stateFormat: p.state,
      asks: asks,
      said: said,
      busy: busy,
      rollingBack: rollingBack,
      answered: answered,
      report: p.lastUpdate?.ui,
      previous: p.previous,
      keepUntil: _at(p.keepUntil),
      points: [
        for (final lp in points)
          LinkPointData(
            link: lp.link,
            version: lp.point.version,
            at: _at(lp.point.at),
            size: lp.point.size,
          ),
      ],
      queue: queue,
      reason: reason?.disabled,
      next: next?.ui,
      offersRollBack: offersRollBack,
      canRollBack: canRollBack,
    );
  }
}

extension BackupsReadOff on BackupsRead {
  /// Why no backup is offered; null when one is.
  BackupsOff? get off => switch (this) {
    BackupsRead.read => null,
    BackupsRead.absent => BackupsOff.absent,
    BackupsRead.unreadable => BackupsOff.unreadable,
    BackupsRead.unknown => BackupsOff.notReadYet,
    BackupsRead.failed => BackupsOff.readFailed,
  };
}
