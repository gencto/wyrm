import 'package:flutter/widgets.dart';
import 'package:localization/localization.dart';

import '../models/tone.dart';
import '../pages/links_data.dart';
import 'task_sheet.dart';

/// The update sheet of a package (boards `LinkUpdate*`, spec
/// `docs/design/specs/updates-backups.md` §1), worded from typed values:
/// the review, the progress, the result, or the restore points alone. Its
/// options report through [onTakePoint], [onAutoRollback] and
/// [onAcceptNew]; the rollback link of the newest restore point through
/// [onRollBack].
TaskSheetVm linkUpdateSheet(
  LinkUpdateData d, {
  ValueChanged<bool>? onTakePoint,
  ValueChanged<bool>? onAutoRollback,
  ValueChanged<bool>? onAcceptNew,
  VoidCallback? onRollBack,
}) => switch (d.stage) {
  LinkUpdateReviewStage() => _review(
    d,
    onTakePoint: onTakePoint,
    onAutoRollback: onAutoRollback,
    onAcceptNew: onAcceptNew,
  ),
  LinkUpdateProgressStage(:final checked) => _progress(d, checked),
  LinkUpdateResultStage(:final report) => _result(d, report, onRollBack),
  LinkUpdatePointsStage() => _points(d),
};

String _point(LinkPointData p) => p.version.isEmpty
    ? S.current.updPointBeforeRestore(p.link)
    : S.current.updPointBeforeUpdate(p.link, p.version);

String _pointNote(LinkPointData p) =>
    '${Formats.dateTime(p.at)} · ${Formats.bytes(p.size)}';

/// A package that was never updated here: its version and the restore
/// points of its links (a link replaced from a backup has one).
TaskSheetVm _points(LinkUpdateData d) {
  final l = S.current;
  return TaskSheetVm(
    title: l.updVersionsOf(d.name),
    sub: '${d.version} · ${l.updLinksCount(d.links.length)}',
    blocks: [
      SheetText(l.updNeverUpdated),
      SheetLabel(l.updPoints),
      if (d.points.isEmpty) SheetText(l.updNoPoints, small: true),
      for (final p in d.points)
        SheetRow(divider: true, text: _point(p), note: _pointNote(p)),
    ],
    secondary: l.updClose,
  );
}

TaskSheetVm _review(
  LinkUpdateData d, {
  ValueChanged<bool>? onTakePoint,
  ValueChanged<bool>? onAutoRollback,
  ValueChanged<bool>? onAcceptNew,
}) {
  final l = S.current;
  final n = d.links.length;
  final hot = d.wasm;
  final to = d.official ? d.latest : '';
  final needsAccept = d.asks != null;
  return TaskSheetVm(
    title: d.official
        ? l.updTitle(d.name, d.version, to)
        : l.updTitleCustom(d.name, d.version),
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
        SheetText(l.updFromFileNote(d.name)),
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
      else if (d.changesState)
        SheetCard(
          tone: .warn,
          title: l.updStateChanges(d.stateFormat),
          detail: l.updStateChangesNote,
        )
      else
        SheetCard(
          title: l.updStateSame(d.stateFormat),
          detail: l.updStateSameNote,
        ),
      SheetLabel(l.updBefore),
      SheetOption(
        label: l.updOptPoint,
        value: d.takePoint || d.changesState,
        enabled: !d.changesState,
        reason: d.changesState ? l.updOptPointLocked : null,
        onChanged: onTakePoint,
      ),
      SheetOption(
        label: l.updOptAuto,
        value: d.autoRollback,
        onChanged: onAutoRollback,
      ),
      if (needsAccept)
        SheetOption(
          label: l.updOptAccept,
          value: d.acceptNew,
          onChanged: onAcceptNew,
        ),
      if (d.queue.isNotEmpty) ...[
        SheetLabel(l.updThen),
        for (final q in d.queue) SheetRow(text: q),
      ],
    ],
    note: d.reason?.text ?? l.updNeedsConfig,
    secondary: l.cancel,
    primary: d.official ? l.updDo(n) : l.updChooseArchive,
    primaryEnabled: d.reason == null && (!needsAccept || d.acceptNew),
    primaryReason: d.reason?.text ?? (needsAccept ? l.acceptFirst : null),
    busy: d.busy,
  );
}

TaskSheetVm _progress(LinkUpdateData d, LinkUpdateReport? r) {
  final l = S.current;
  // The action answers once the links restarted; until then the broker
  // tells nothing of its steps.
  final answered = r != null;
  final first = answered ? SheetStepState.done : SheetStepState.todo;
  return TaskSheetVm(
    title: l.updUpdating(d.name),
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

TaskSheetVm _result(
  LinkUpdateData d,
  LinkUpdateReport r,
  VoidCallback? onRollBack,
) {
  final l = S.current;
  // the version a rollback goes to: as a link of the newest restore point
  // when this user may, and as the first button when the result offers it
  final kept = d.kept;
  final allowedTo = kept != null && kept.allowed ? kept.version : null;
  final offeredTo = kept != null && kept.offered ? kept.version : null;
  final (Tone tone, String title, String text) = switch (r.end) {
    LinkUpdateRolledBack() => (
      Tone.warn,
      // A rollback keeps the update's `from` and `to`: the links are
      // back on `from`.
      l.updRolledBackTo(r.from),
      r.reason.isEmpty ? l.updRolledBackNote : r.reason,
    ),
    LinkUpdateFailed() => (
      Tone.warn,
      l.updFailed(r.to),
      r.reason.isEmpty ? l.updFailedNote : r.reason,
    ),
    LinkUpdateUnknown(:final word) => (
      Tone.warn,
      l.updUnknownResult(word),
      r.reason.isEmpty ? l.updUnknownResultNote : r.reason,
    ),
    _ when r.gone > 0 => (Tone.warn, l.updRuns(r.to), r.reason),
    _ => (Tone.good, l.updRuns(r.to), l.updRunsNote(r.links.join(', '))),
  };
  final rolled = r.end is LinkUpdateRolledBack;
  final first = r.links.isEmpty ? null : r.links.first;
  return TaskSheetVm(
    title: rolled ? l.updTitleRolledBack(d.name) : l.updTitleDone(d.name),
    sub:
        '${r.from} → ${r.to} · ${l.updLinksCount(r.links.length)} · '
        '${Formats.dateTime(r.at)}',
    pill: switch (r.end) {
      LinkUpdateRolledBack() => l.updPillRolledBack,
      LinkUpdateFailed() => l.updPillFailed,
      LinkUpdateUnknown() => l.updPillUnknown,
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
      for (final (i, p) in d.points.indexed)
        SheetRow(
          divider: true,
          text: _point(p),
          note: _pointNote(p),
          actionLabel: i == 0 && allowedTo != null
              ? l.updRollBackTo(allowedTo)
              : null,
          onAction: i == 0 && allowedTo != null ? onRollBack : null,
        ),
      if (d.kept case LinkKeptVersion(:final version, :final until))
        SheetText(
          l.updKeptUntil(version, Formats.dateTime(until)),
          small: true,
        ),
    ],
    note: rolled ? l.updAuditRollback : l.updAuditUpdate,
    secondary: l.updClose,
    primary: offeredTo != null
        ? l.updRollBackTo(offeredTo)
        : (rolled
              ? l.updOpenLog
              : (first == null ? null : l.updOpenLink(first))),
    primaryQuiet: offeredTo != null,
    primaryEnabled: offeredTo == null || d.reason == null,
    primaryReason: d.reason?.text,
    busy: d.rollingBack,
  );
}
