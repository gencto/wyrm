import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/pick_chip_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/save_plan_action.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/assistant/task_card.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/reason_dialog.dart';
import 'package:ui/overlays/search_palette.dart';

import '../common/files.dart';
import '../mappers/assistant_mappers.dart';

// The dialogs the Assistant opens over [BuildContext] (studio-rules §4: a
// connector takes no context): each asks the person, then starts one
// action through the store above it. The words are the dialogs' own.

/// Reject asks for a reason, then rejects task [id] with it.
Future<void> rejectTask(BuildContext context, String id) async {
  final reason = await ReasonDialog.ask(
    context,
    title: S.current.rejectPlanTitle,
    message: S.current.rejectPlanNote,
    hint: S.current.rejectPlanHint,
    confirm: S.current.reject,
    cancel: S.current.cancel,
  );
  if (reason != null && context.mounted) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      RejectTaskAction(id, reason: reason),
    );
  }
}

/// Cancel asks first, then cancels task [id].
Future<void> cancelTask(BuildContext context, String id) async {
  final sure = await ConfirmDialog.ask(
    context,
    title: S.current.cancelTask,
    message: S.current.failedNote,
    confirm: S.current.cancelTask,
    cancel: S.current.cancel,
  );
  if (sure && context.mounted) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      CancelTaskAction(id),
    );
  }
}

/// *+ prefix*: asks for a key prefix, then stages it. [root] is the site
/// on screen (`wy/<site>`), for the example the dialog shows.
Future<void> addPrefix(BuildContext context, {required String? root}) async {
  final p = await ReasonDialog.ask(
    context,
    title: S.current.addPrefixTitle,
    message: S.current.addPrefixNote(
      '${root ?? 'wy/<site>'}/downstream/modbus',
    ),
    hint: S.current.addPrefixHint,
    confirm: S.current.addPrefixButton,
    cancel: S.current.cancel,
  );
  if (p != null && p.trim().isNotEmpty && context.mounted) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      StageAgentParamAction.addPrefix(p.trim()),
    );
  }
}

/// The drawer's second button was pressed ([tile], spec `assistant.md`
/// §5): while the plan waits the tile is a draft the person copies (asked
/// first, [copyDraft]); after the task it is a follow-up ask, which
/// [onPick] starts.
Future<void> pressSecond(
  BuildContext context,
  SuggestionTileVm? tile,
  ValueChanged<String>? onPick,
) async {
  switch (tile) {
    case final s? when s.note == TileNote.draft:
      await copyDraft(context, label: s.label, detail: s.detail);
    case final s?:
      onPick?.call(s.id);
    case null:
      break;
  }
}

/// The drawer's second tile while the plan waits (spec §5): the model's
/// words as a draft the person copies and sends themselves. Nothing is
/// asked: an ask would replace a plan the person may still approve.
Future<void> copyDraft(
  BuildContext context, {
  required String label,
  required String detail,
}) async {
  final copy = await ConfirmDialog.ask(
    context,
    title: S.current.draftTitle,
    message: '$label\n\n$detail\n\n${S.current.draftNote}',
    confirm: S.current.copyText,
    cancel: S.current.cancel,
    danger: false,
  );
  if (!copy) {
    return;
  }
  await Clipboard.setData(ClipboardData(text: detail.isEmpty ? label : detail));
  if (context.mounted) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      ShowNoticeAction(.draftCopied),
    );
  }
}

/// Save as a plan: the folder is the person's pick, the file is written by
/// [SavePlanAction], and its notice says where it went and which secret
/// arguments were left out of it.
Future<void> savePlan(BuildContext context, String id) async {
  final file = await saveInto(
    'task-$id.plan.json',
    fallback: 'plan.json',
    dialogTitle: S.current.savePlanTitle(id),
  );
  if (file == null || !context.mounted) {
    return;
  }
  await StoreProvider.dispatchAndWait<AppState>(
    context,
    SavePlanAction(
      id,
      write: file.write,
      onDone: file.commit,
      onDiscard: file.discard,
      path: file.path,
    ),
  );
}

/// *+ from Explorer*: a key picker over the nodes Explorer has read on the
/// site on screen (the selection first), or a key typed in full or below
/// the site; the pick is an `@` chip. What is offered is read when the
/// picker opens and again as the person types ([chipChoicesOf],
/// [typedChipOf]); [PickChipAction] takes the pick only if it still holds.
Future<void> pickContextKey(BuildContext context) async {
  final choices = chipChoicesOf(StoreProvider.state<AppState>(context));
  if (choices == null) {
    return;
  }
  final picked = await SearchPalette.show<String?>(
    context,
    hint: S.current.pickKeyHint(choices.site),
    entries: [
      for (final c in choices.entries)
        SearchEntryVm(
          id: c.key,
          title: c.title,
          icon: c.icon,
          detail: c.selected ? S.current.pickKeySelected : shortKey(c.key),
        ),
    ],
    goTo: (text) =>
        switch (typedChipOf(StoreProvider.state<AppState>(context), text)) {
          null => null,
          // said, not offered: it has no key to pick
          (:final key, reads: false) => SearchEntryVm(
            id: null,
            title: S.current.pickKeyOutside(shortKey(key)),
            icon: 'ui_close',
          ),
          (:final key, reads: true) => SearchEntryVm(
            id: key,
            title: S.current.pickKeyTyped(shortKey(key)),
            icon: 'ui_chevron_right',
          ),
        },
  );
  if (picked != null && context.mounted) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      PickChipAction(picked),
    );
  }
}

/// A button of the card of task [task] was pressed: one that asks first
/// opens its dialog (Reject, Cancel, Save as a plan); any other starts its
/// action at once through [onStart].
Future<void> pressTaskButton(
  BuildContext context,
  TaskButtonVm b, {
  required String? task,
  required ValueChanged<TaskButtonVm> onStart,
}) async {
  if (task == null) {
    return;
  }
  switch (b.button) {
    case TaskButton.reject:
      await rejectTask(context, task);
    case TaskButton.cancel:
      await cancelTask(context, task);
    case TaskButton.save:
      await savePlan(context, task);
    case TaskButton.followUp ||
        TaskButton.approve ||
        TaskButton.replacement ||
        TaskButton.explorer ||
        TaskButton.trend:
      onStart(b);
  }
}
