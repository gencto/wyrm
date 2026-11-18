import 'package:equatable/equatable.dart';
import 'package:models/agent_params.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_mode.dart';
import 'package:models/staged_change.dart';
import 'package:models/task_suggestion.dart';

import '../common/memo.dart';
import '../redux/app_state.dart';
import 'holds.dart';

// What the Assistant shows that is decided from the state and one task
// (studio-rules §3): the card under a task, the drawer's second button,
// its timeline, and the parts of the state a view of it is made of. The
// connector reads these through `app/lib/mappers/assistant_shown.dart`.

/// What the card under a task says and offers: one case per state the
/// task is in, with why each of its buttons cannot be pressed.
sealed class TaskStanding {
  const TaskStanding();
}

/// Another task took the plan's place: it is never approved; the way to
/// the task [by] that replaced it.
final class StandingReplaced extends TaskStanding {
  const StandingReplaced(this.by);

  final String by;
}

/// The plan waits: what Approve signs ([note]), how many changes run once
/// approved ([runs], 0 with nothing ticked), and why Reject and Approve
/// cannot be pressed.
final class StandingApproval extends TaskStanding {
  const StandingApproval({
    required this.note,
    required this.runs,
    required this.rejectHold,
    required this.approveHold,
  });

  final ApprovalNote note;
  final int runs;
  final Hold? rejectHold;
  final Hold? approveHold;
}

/// The assistant asked and waits for the answer.
final class StandingAnswer extends TaskStanding {
  const StandingAnswer({required this.cancelHold});

  final Hold? cancelHold;
}

/// The assistant plans, the plan runs, or the model reviews a stopped run.
final class StandingWorking extends TaskStanding {
  const StandingWorking({required this.cancelHold});

  final Hold? cancelHold;
}

/// The plan ran: the steps it left out, the node it changed, the point
/// whose trend shows it, whether there is a plan to save, and why the
/// steps left out cannot be asked for.
final class StandingDone extends TaskStanding {
  const StandingDone({
    required this.task,
    required this.leftOut,
    required this.changedNode,
    required this.trendPoint,
    required this.savable,
    required this.followUpHold,
  });

  final String task;
  final List<int> leftOut;
  final String? changedNode;
  final String? trendPoint;
  final bool savable;
  final Hold? followUpHold;
}

/// The task failed before any step ran: why, in the link's words.
final class StandingFailed extends TaskStanding {
  const StandingFailed(this.error);

  final String? error;
}

/// The drawer's second button (spec `assistant.md` §5): the model's offer,
/// as a [draft] the person copies while the plan waits (an ask would
/// replace a plan they may still approve), else as a follow-up ask with
/// why it cannot be picked ([hold]).
final class SecondOffer {
  const SecondOffer(this.suggestion, {required this.draft, this.hold});

  final TaskSuggestion suggestion;
  final bool draft;
  final Hold? hold;
}

/// One argument of a plan step as the plan card shows it: its [text] as
/// it is sent, or null when it is masked (a secret, or a schema that is
/// not known and not looked at).
final class ShownArg extends Equatable {
  const ShownArg(this.name, this.text);

  final String name;
  final String? text;

  @override
  List<Object?> get props => [name, text];
}

/// The tasks of the list, newest first: those under way, and those that
/// ended.
final class TaskGroups {
  const TaskGroups({required this.now, required this.earlier});

  final List<AgentTask> now;
  final List<AgentTask> earlier;
}

/// The keys *+ from Explorer* offers: the selection and the point
/// [first], then the [rest] Explorer read.
final class ChipOffer {
  const ChipOffer({required this.first, required this.rest});

  final List<String> first;
  final List<String> rest;
}

/// A key typed in the picker: the plain node [key] it names, and whether
/// the agent reads it.
final class TypedChip {
  const TypedChip(this.key, {required this.reads});

  final String key;
  final bool reads;
}

/// The update staged for the agent link: the [change], the params it
/// sends and the [base] they were made from.
final class StagedAgentParams {
  const StagedAgentParams({
    required this.change,
    required this.params,
    required this.base,
  });

  final StagedChange change;
  final AgentParams params;
  final AgentParams base;
}

/// The agent link's approval mode and prefixes as they will be: from the
/// update staged for it, else as read. [mode] is null when it is not
/// known.
final class AgentParamsShown {
  const AgentParamsShown({
    required this.mode,
    required this.prefixes,
    required this.staged,
  });

  final ApprovalMode? mode;
  final List<String> prefixes;
  final bool staged;
}

/// How far the steps of a plan that change something were checked: [now]
/// against the live tree, [atRun] only when they run.
final class PlanChecks extends Equatable {
  const PlanChecks({required this.now, required this.atRun});

  final int now;
  final int atRun;

  @override
  List<Object?> get props => [now, atRun];
}

/// A ticked row of *Same for more units?*: the suggestion it belongs to
/// and the node's key.
final class RowPick extends Equatable {
  const RowPick(this.suggestion, this.key);

  final String suggestion;
  final String key;

  @override
  List<Object?> get props => [suggestion, key];
}

/// The state read through its selectors.
final class _Read with Selectors {
  _Read(this.state);

  @override
  final AppState state;
}

final _tabKeys = Memo<List<String>>();
final _drawerKeys = Memo<List<String>>();

/// What a view of the Assistant reads of [s], each the very object it
/// read: what is made of it is kept (`Memo`) while every input is the same
/// object. The tasks, the assistant's own slice, the site (who asks, with
/// which rights), the staged changes (the agent's params as they will be),
/// the waits it shows, the language, and the live values of
/// [AssistantView.assistantLiveKeys] only, never the whole map. The
/// [drawer] also reads Explorer's point and its history (the timeline).
/// It reads no clock.
List<Object?> assistantInputsOf(AppState s, {required bool drawer}) {
  final r = _Read(s);
  final keys = (drawer ? _drawerKeys : _tabKeys).of(
    [s.tasks, s.assistant, s.site],
    () => r.assistantLiveKeys(drawer: drawer),
  );
  final nodes = s.nodes;
  return [
    s.tasks,
    s.assistant,
    s.site,
    s.changes.table,
    s.language,
    r.assistant.isWaiting,
    r.links.isWaiting,
    r.assistant.isAsking,
    r.assistant.isApproving,
    r.tasks.isAnswering,
    for (final k in keys) s.live.values[k],
    if (drawer) ...[
      nodes.point,
      nodes.historyKey,
      nodes.history,
      nodes.historyAt,
      nodes.historyRange,
      nodes.historyWindow,
      r.nodes.historyLoading,
      if (r.timelinePoint case final p?) nodes.table[p],
    ],
  ];
}
