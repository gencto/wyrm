import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/save_plan_action.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/node_info.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/assistant/task_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/reason_dialog.dart';
import 'package:ui/overlays/search_palette.dart';

import '../common/files.dart';

// The dialogs the Assistant opens over [BuildContext] (studio-rules §4: a
// connector takes no context): each asks the person, then starts one
// action through the store above it. The words are the dialogs' own.

/// The store's state seen through the selectors, at the moment a dialog
/// opens.
final class _Read with Selectors {
  _Read(this.state);

  @override
  final AppState state;
}

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

/// *+ prefix*: asks for a key prefix, then stages it.
Future<void> addPrefix(BuildContext context) async {
  final root = _Read(StoreProvider.state<AppState>(context)).site.root;
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
      ShowNoticeAction(S.current.draftCopied),
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
      saved: (left) => (
        title: S.current.planSaved(file.path),
        detail: left.isEmpty
            ? null
            : S.current.planSavedSecrets(left.join('; ')),
      ),
    ),
  );
}

/// *+ from Explorer*: a key picker over the nodes Explorer has read on the
/// site on screen (the selection first), or a key typed in full or below
/// the site; the pick is an `@` chip. Only the keys the selectors offer
/// (plain node keys of this site the agent reads) can be picked.
Future<void> pickContextKey(BuildContext context) async {
  final read = _Read(StoreProvider.state<AppState>(context));
  final root = read.site.root;
  if (root == null || read.chipHold != null) {
    return;
  }
  final (:first, :rest) = read.chipChoices;
  SearchEntryVm entry(String k, {String? detail}) {
    final info = read.nodes.table[k];
    return SearchEntryVm(
      id: k,
      title: switch (info) {
        NodeInfo(:final display?, :final name)
            when display.trim().isNotEmpty && display != name =>
          display,
        final n => n?.name ?? shortKey(k),
      },
      icon: AppIcon.nodeName(
        key: k,
        root: root,
        profile: info?.profile,
        type: info?.type,
      ),
      detail: detail ?? shortKey(k),
    );
  }

  final picked = await SearchPalette.show(
    context,
    hint: S.current.pickKeyHint(root.split('/').last),
    entries: [
      for (final k in first) entry(k, detail: S.current.pickKeySelected),
      for (final k in rest) entry(k),
    ],
    goTo: (text) => switch (read.typedChip(text)) {
      null => null,
      // said, not offered: picking it does nothing
      (:final key, reads: false) => SearchEntryVm(
        id: '',
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
  if (picked == null || picked.isEmpty || !context.mounted) {
    return;
  }
  final now = _Read(StoreProvider.state<AppState>(context));
  if (now.typedChip(picked)?.reads ?? false) {
    await StoreProvider.dispatchAndWait<AppState>(
      context,
      SetChipAction(picked),
    );
  }
}

/// What the buttons of a task's card that start their action at once do,
/// for the task [task] on screen. Compared on the task and on which of
/// them react: the callbacks are behaviour.
final class TaskButtonActions extends Equatable {
  const TaskButtonActions({
    this.task,
    this.approve,
    this.replacement,
    this.explorer,
    this.trend,
    this.followUp,
  });

  final String? task;
  final VoidCallback? approve;
  final VoidCallback? replacement;
  final VoidCallback? explorer;
  final VoidCallback? trend;

  /// Asks for the steps a run left out, in the words the button says.
  final ValueChanged<String>? followUp;

  @override
  List<Object?> get props => [
    task,
    approve != null,
    replacement != null,
    explorer != null,
    trend != null,
    followUp != null,
  ];
}

/// A button of a task's card was pressed: one that asks first opens its
/// dialog (Reject, Cancel, Save as a plan); the others start their action
/// at once through [actions].
Future<void> pressTaskButton(
  BuildContext context,
  TaskButtonVm b,
  TaskButtonActions actions,
) async {
  final id = actions.task;
  if (id == null) {
    return;
  }
  switch (b.button) {
    case TaskButton.reject:
      await rejectTask(context, id);
    case TaskButton.cancel:
      await cancelTask(context, id);
    case TaskButton.save:
      await savePlan(context, id);
    case TaskButton.followUp:
      actions.followUp?.call(b.says);
    case TaskButton.approve:
      actions.approve?.call();
    case TaskButton.replacement:
      actions.replacement?.call();
    case TaskButton.explorer:
      actions.explorer?.call();
    case TaskButton.trend:
      actions.trend?.call();
  }
}
