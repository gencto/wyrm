import 'package:localization/localization.dart';
import 'package:models/package_info.dart';
import 'package:models/restore_point.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

import 'sizes.dart';

/// Which screen of an update the sheet shows.
enum UpdateStage { review, progress, result }

/// What the update sheet of one package is built from (boards
/// `LinkUpdate*`, spec `docs/design/specs/updates-backups.md` §1).
final class UpdateSheetData {
  const UpdateSheetData({
    required this.package,
    required this.links,
    required this.follow,
    this.official = true,
    this.title,
    this.summary,
    this.takePoint = true,
    this.autoRollback = true,
    this.acceptNew = false,
    this.asks,
    this.said,
    this.busy = false,
    this.rollingBack = false,
    this.seenAt = -1,
    this.points = const [],
    this.queue = const [],
    this.reason,
  });

  /// The package with its live values.
  final PackageInfo package;

  /// The links that run it, by id.
  final List<String> links;

  /// The sheet follows `last_update` (progress or result), else it is the
  /// review.
  final bool follow;

  /// The repository lists it; else it is custom (updated from a file).
  final bool official;

  /// The `title` and `summary` of its catalog row.
  final String? title;
  final String? summary;
  final bool takePoint;
  final bool autoRollback;
  final bool acceptNew;

  /// The broker's answer of an update it did not make: the rights the new
  /// version asks for.
  final String? asks;

  /// What the broker answered to the update or the rollback.
  final String? said;

  /// The update action is in flight.
  final bool busy;
  final bool rollingBack;

  /// `last_update.at` before the action of this sheet; negative when the
  /// sheet only shows what is there.
  final int seenAt;

  /// The restore points of the links: `(link, point)`, newest first.
  final List<(String, RestorePoint)> points;

  /// The packages updated after this one.
  final List<String> queue;

  /// Why the user may not update (`needs config on …`), or null.
  final String? reason;

  UpdateStage get stage {
    if (!follow) {
      return .review;
    }
    final r = package.lastUpdate;
    return busy || r == null || r.at == seenAt || r.result == 'checking'
        ? .progress
        : .result;
  }
}

String _when(int seconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// The update sheet: review, progress, or result.
TaskSheetVm updateSheet(UpdateSheetData d) => switch (d.stage) {
  .review => _review(d),
  .progress => _progress(d),
  .result => _result(d),
};

TaskSheetVm _review(UpdateSheetData d) {
  final l = S.current;
  final p = d.package;
  final n = d.links.length;
  final hot = p.kind == 'wasm';
  final to = d.official ? p.latest : '';
  final needsAccept = d.asks != null;
  return TaskSheetVm(
    title: d.official
        ? l.updTitle(p.name, p.version, to)
        : l.updTitleCustom(p.name, p.version),
    pill: d.official ? l.updOfficial : l.updCustom,
    pillTone: d.official ? .good : .neutral,
    sub: d.official ? l.updSubOfficial(n) : l.updSubCustom(n),
    blocks: [
      if (d.official) ...[
        SheetLabel(l.updWhatIsNew(to)),
        SheetBullets([
          if (d.title case final t? when t.isNotEmpty) t,
          if (d.summary case final s? when s.isNotEmpty) s,
          if ((d.title ?? '').isEmpty && (d.summary ?? '').isEmpty)
            l.updNoNotes,
        ]),
      ] else ...[
        SheetLabel(l.updFromFile),
        SheetText(l.updFromFileNote(p.name)),
      ],
      SheetLabel(l.updWhatChanges),
      SheetCard(
        tone: hot ? .good : .warn,
        title: hot
            ? l.updHotStart(d.links.join(', '))
            : l.updLinksRestart(n, d.links.join(', ')),
        detail: hot ? l.updHotStartNote : l.updLinksRestartNote,
      ),
      SheetCard(title: l.updKept, detail: l.updKeptNote),
      if (needsAccept)
        SheetCard(tone: .warn, title: l.updAsksMore, detail: d.asks)
      else
        SheetCard(title: l.updRights, detail: l.updRightsNote),
      if (!d.official)
        SheetCard(title: l.updStateCustom, detail: l.updStateCustomNote)
      else if (p.changesState)
        SheetCard(
          tone: .warn,
          title: l.updStateChanges(p.state),
          detail: l.updStateChangesNote,
        )
      else
        SheetCard(
          title: l.updStateSame(p.state),
          detail: l.updStateSameNote,
        ),
      SheetLabel(l.updBefore),
      SheetOption(
        id: 'point',
        label: l.updOptPoint,
        value: d.takePoint || p.changesState,
        enabled: !p.changesState,
        reason: p.changesState ? l.updOptPointLocked : null,
      ),
      SheetOption(id: 'auto', label: l.updOptAuto, value: d.autoRollback),
      if (needsAccept)
        SheetOption(id: 'accept', label: l.updOptAccept, value: d.acceptNew),
      if (d.queue.isNotEmpty) ...[
        SheetLabel(l.updThen),
        for (final q in d.queue) SheetRow(text: q),
      ],
    ],
    note: d.reason ?? l.updNeedsConfig,
    secondary: l.cancel,
    primary: d.official ? l.updDo(n) : l.updChooseArchive,
    primaryEnabled: d.reason == null && (!needsAccept || d.acceptNew),
    primaryReason: d.reason ?? (needsAccept ? l.acceptFirst : null),
    busy: d.busy,
  );
}

TaskSheetVm _progress(UpdateSheetData d) {
  final l = S.current;
  final p = d.package;
  final r = d.package.lastUpdate;
  // The action answers once the links restarted; until then the broker
  // tells nothing of its steps.
  final answered =
      !d.busy && r != null && r.at != d.seenAt && r.result == 'checking';
  final first = answered ? SheetStepState.done : SheetStepState.todo;
  return TaskSheetVm(
    title: l.updUpdating(p.name),
    sub: l.updUpdatingSub,
    pill: answered ? l.updChecking : l.updWorking,
    pillTone: .ember,
    blocks: [
      SheetSteps([
        SheetStep(
          l.updStepPoint,
          answered ? .done : .now,
          detail: answered && r.restorePoint ? l.updStepPointSaved : null,
        ),
        SheetStep(
          l.updStepPackage,
          first,
          detail: answered ? '${r.from} → ${r.to}' : null,
        ),
        SheetStep(
          l.updStepRestart,
          first,
          detail: answered ? r.links.join(', ') : null,
        ),
        SheetStep(
          l.updStepNodes,
          answered ? .now : .todo,
          detail: answered
              ? l.updStepNodesCount(r.kept + r.added, r.gone)
              : null,
        ),
      ]),
      if (d.said case final m? when m.isNotEmpty) SheetText(m, small: true),
      if (d.queue.isNotEmpty) ...[
        SheetLabel(l.updThen),
        for (final q in d.queue) SheetRow(text: q),
      ],
    ],
    note: l.updLeave,
    secondary: l.updStopAndRollBack,
    primary: l.updUpdatingButton,
    primaryEnabled: false,
    busy: true,
  );
}

TaskSheetVm _result(UpdateSheetData d) {
  final l = S.current;
  final p = d.package;
  final r = p.lastUpdate!;
  final (Tone tone, String title, String text) = switch (r.result) {
    'rolled_back' => (
      Tone.warn,
      l.updRolledBackTo(r.to),
      r.reason.isEmpty ? l.updRolledBackNote : r.reason,
    ),
    'failed' => (
      Tone.warn,
      l.updFailed(r.to),
      r.reason.isEmpty ? l.updFailedNote : r.reason,
    ),
    _ when r.gone > 0 => (Tone.warn, l.updRuns(r.to), r.reason),
    _ => (Tone.good, l.updRuns(r.to), l.updRunsNote(r.links.join(', '))),
  };
  final rolled = r.result == 'rolled_back';
  final canRollBack = p.previous != null && d.reason == null;
  final offerRollBack =
      p.previous != null && (r.result == 'failed' || (!rolled && r.gone > 0));
  final first = r.links.isEmpty ? null : r.links.first;
  return TaskSheetVm(
    title: rolled ? l.updTitleRolledBack(p.name) : l.updTitleDone(p.name),
    sub:
        '${r.from} → ${r.to} · ${l.updLinksCount(r.links.length)} · '
        '${_when(r.at)}',
    pill: switch (r.result) {
      'rolled_back' => l.updPillRolledBack,
      'failed' => l.updPillFailed,
      _ => l.updPillDone,
    },
    pillTone: tone,
    blocks: [
      SheetBanner(title: title, text: text, tone: tone),
      SheetLabel(l.updNodes),
      SheetTiles([
        SheetTile('${r.kept}', l.updKeptTile),
        SheetTile(
          r.added > 0 ? '+${r.added}' : '0',
          l.updNewTile,
          tone: r.added > 0 ? .good : .neutral,
        ),
        SheetTile(
          '${r.gone}',
          l.updGoneTile,
          tone: r.gone > 0 ? .warn : .neutral,
        ),
      ]),
      for (final k in r.newKeys.take(10))
        SheetRow(sign: '+', text: k, tone: .good),
      for (final k in r.goneKeys.take(10))
        SheetRow(sign: '!', text: k, tone: .warn),
      SheetLabel(l.updPoints),
      if (d.points.isEmpty) SheetText(l.updNoPoints, small: true),
      for (final (i, (link, point)) in d.points.indexed)
        SheetRow(
          divider: true,
          text: point.version.isEmpty
              ? l.updPointBeforeRestore(link)
              : l.updPointBeforeUpdate(link, point.version),
          note: '${_when(point.at)} · ${bytesText(point.size)}',
          action: i == 0 && canRollBack ? 'rollback' : null,
          actionLabel: i == 0 && canRollBack
              ? l.updRollBackTo(p.previous!)
              : null,
        ),
      if (p.previous case final v?)
        SheetText(l.updKeptUntil(v, _when(p.keepUntil)), small: true),
    ],
    note: rolled ? l.updAuditRollback : l.updAuditUpdate,
    secondary: l.updClose,
    primary: offerRollBack
        ? l.updRollBackTo(p.previous!)
        : (rolled
              ? l.updOpenLog
              : (first == null ? null : l.updOpenLink(first))),
    primaryQuiet: offerRollBack,
    primaryEnabled: !offerRollBack || d.reason == null,
    primaryReason: d.reason,
    busy: d.rollingBack,
  );
}

/// What the primary button of the sheet does at this stage.
String updatePrimary(UpdateSheetData d) {
  switch (d.stage) {
    case .review:
      return d.official ? 'update' : 'file';
    case .progress:
      return '';
    case .result:
      final r = d.package.lastUpdate!;
      final rolled = r.result == 'rolled_back';
      if (d.package.previous != null &&
          (r.result == 'failed' || (!rolled && r.gone > 0))) {
        return 'rollback';
      }
      return rolled ? 'log' : 'open';
  }
}
