import 'package:business/wyrm/link_update.dart';
import 'package:models/link_state.dart';
import 'package:models/links_tab.dart';
import 'package:models/package_info.dart';
import 'package:models/package_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/update_next.dart';
import 'package:models/update_report.dart';
import 'package:models/update_result.dart';
import 'package:models/update_stage.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/pages/links_data.dart';

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
  /// why the user may not decide.
  QuarantineData data({List<ParamFieldVm>? fields, String? reason}) =>
      QuarantineData(
        node: node,
        cn: cn,
        broker: kind == QuarantineKind.broker,
        from: from,
        via: via.unlock,
        deauthorized: deauthorized,
        firstSeen: firstSeen,
        key: key,
        fields: fields,
        reason: reason,
      );
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
      reason: reason,
      next: next?.ui,
      offersRollBack: offersRollBack,
      canRollBack: canRollBack,
    );
  }
}
