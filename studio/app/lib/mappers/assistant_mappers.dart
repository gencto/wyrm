import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/assistant_view.dart';
import 'package:business/wyrm/decode/node_glyph.dart';
import 'package:business/wyrm/holds.dart';
import 'package:business/wyrm/task_facts.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_mode.dart';
import 'package:models/approval_refusal.dart';
import 'package:models/assistant_panel.dart';
import 'package:models/audit_entry.dart';
import 'package:models/finding_refusal.dart';
import 'package:models/plan_step.dart';
import 'package:models/quality.dart';
import 'package:models/step_args_note.dart';
import 'package:models/step_check.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_status.dart';
import 'package:models/step_wait.dart';
import 'package:models/task_event.dart';
import 'package:models/task_event_kind.dart';
import 'package:models/task_finding.dart';
import 'package:models/task_question.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/blocked.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/found_card.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/rights_panel.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/assistant/task_card.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/pages/assistant_page.dart';

import 'icon_mappers.dart';
import 'rights_mappers.dart';

// The agent task's domain as the Assistant draws it (studio-rules §3): one
// exhaustive switch per domain enum, and the rows built from a task's
// parts. What is computed from state is a selector in `business`
// (`AssistantScreen`); what is computed from one task is `TaskFacts`.

extension ComposerCueHint on ComposerCue {
  ComposerHint get hint => switch (this) {
    ComposerCue.ask => .ask,
    ComposerCue.answer => .answer,
    ComposerCue.planning => .planning,
    ComposerCue.awaiting => .awaiting,
    ComposerCue.running => .running,
    ComposerCue.done => .done,
    ComposerCue.failed => .failed,
    ComposerCue.drawer => .drawer,
  };
}

extension TaskStateBadge on TaskState {
  TaskBadge get badge => switch (this) {
    TaskState.planning => .planning,
    TaskState.awaitingAnswer => .awaitingAnswer,
    TaskState.awaitingApproval => .awaitingApproval,
    TaskState.running => .running,
    TaskState.done => .done,
    TaskState.failed => .failed,
  };
}

extension ApprovalModeView on ApprovalMode {
  AgentModeVm get view => switch (this) {
    ApprovalMode.write => .write,
    ApprovalMode.config => .config,
    ApprovalMode.never => .never,
  };
}

/// The mode under which a pick's plan may write without a person, as the
/// cautions say it: [unknown] (the agent's settings did not read) keeps
/// every caution; else the [mode] that lets it (`config`, `never`), or
/// null for `write`.
AgentModeVm? unattendedView(ApprovalMode? mode, {required bool unknown}) =>
    unknown ? .unknown : mode?.view;

extension AgentModeDomain on AgentModeVm {
  /// The mode a pick on *What it may do* stages; null for [unknown],
  /// which is never offered as a pick.
  ApprovalMode? get domain => switch (this) {
    AgentModeVm.write => .write,
    AgentModeVm.config => .config,
    AgentModeVm.never => .never,
    AgentModeVm.unknown => null,
  };
}

extension AssistantPanelTab on AssistantPanel {
  AssistantTab get tab => switch (this) {
    AssistantPanel.task => .task,
    AssistantPanel.rights => .rights,
  };
}

extension AssistantTabPanel on AssistantTab {
  AssistantPanel get panel => switch (this) {
    AssistantTab.task => .task,
    AssistantTab.rights => .rights,
  };
}

extension StepKindVerb on StepKind {
  StepVerb get verb => switch (this) {
    StepKind.set => .set,
    StepKind.invoke => .invoke,
    StepKind.wait => .wait,
    StepKind.expect => .expect,
    StepKind.sleep => .sleep,
  };
}

extension StepStatusOutcome on StepStatus {
  StepOutcome get outcome => switch (this) {
    StepStatus.ok => .ok,
    StepStatus.failed => .failed,
    StepStatus.skipped => .skipped,
  };

  RunStatus get run => switch (this) {
    StepStatus.ok => .ok,
    StepStatus.failed => .failed,
    StepStatus.skipped => .skipped,
  };
}

extension StepWaitRun on StepWait {
  RunStatus get run => switch (this) {
    StepWait.running => .running,
    StepWait.waiting => .waiting,
  };
}

extension StepArgsNoteVm on StepArgsNote {
  ArgsNote get vm => switch (this) {
    StepArgsNote.masked => .masked,
    StepArgsNote.secret => .secret,
  };
}

extension StepNoteView on StepNote {
  StepNoteVm get vm => switch (this) {
    StepNoteNeeds(:final step) => StepNeeds(step),
    StepNoteLeftOut() => const StepLeftOut(),
    StepNoteByAgent() => const StepByAgent(),
    StepNoteAfter(:final steps) => StepAfter(steps),
  };
}

extension StepCheckView on StepCheck {
  StepCheckVm get view => switch (this) {
    StepCheck.now => .now,
    StepCheck.atRun => .atRun,
  };
}

extension FindingRefusalView on FindingRefusal {
  FoundRefusal get view => switch (this) {
    FindingRefusal.rightsUnknown => .rightsUnknown,
    FindingRefusal.rightsExpired => .rightsExpired,
    FindingRefusal.outsideRights => .outsideRights,
    FindingRefusal.limit => .limit,
    FindingRefusal.invalid => .invalid,
  };
}

extension QualityFoundMark on Quality? {
  /// The mark of a finding from its node's live value; [FoundMark.none]
  /// when none was read.
  FoundMark get found => switch (this) {
    Quality.good => .good,
    Quality.bad => .bad,
    Quality.uncertain => .uncertain,
    null => .none,
  };
}

extension HoldBlocked on Hold {
  Blocked get blocked => switch (this) {
    HoldNoAgent() => const BlockedNoAgent(),
    HoldBusy() => const BlockedBusy(),
    HoldLacks(:final lack) => BlockedLacks(lack.needs),
    HoldOtherSite(:final site) => BlockedOtherSite(site),
    HoldNoRecord() => const BlockedNoRecord(),
    HoldNoneTicked() => const BlockedNoneTicked(),
    HoldReveal(:final step) => BlockedReveal(step),
    HoldFollow() => const BlockedFollow(),
    HoldPickOne() => const BlockedPickOne(),
    HoldNoRows() => const BlockedNoRows(),
    HoldNoSite() => const BlockedNoSite(),
    HoldChipsFull(:final max) => BlockedChipsFull(max),
  };
}

extension ApprovalNoteView on ApprovalNote {
  TaskNoteVm get note => switch (this) {
    ApprovalNoRecord() => const TaskNoteNoRecord(),
    ApprovalOtherSite(:final site) => TaskNoteOtherSite(site),
    ApprovalRefused(:final why) => switch (why) {
      ApprovalRefusalChanged() => const TaskNoteRefused.changed(),
      ApprovalRefusalUnseen(:final step) => TaskNoteRefused.unseen(step),
      ApprovalRefusalSaid(:final message) => TaskNoteRefused(message),
    },
    ApprovalWaiting() => const TaskNoteWaiting(),
    ApprovalSigns(:final role, :final byAgent) => TaskNoteSigns(
      role: role,
      byAgent: byAgent,
    ),
  };
}

extension TaskEventLine on TaskEvent {
  ConversationEventVm get line => switch (kind) {
    TaskEventKind.ask => ConversationEventVm(kind: .ask, text: text),
    TaskEventKind.answer => ConversationEventVm(kind: .answer, text: text),
    TaskEventKind.text => ConversationEventVm(kind: .text, text: text),
    TaskEventKind.tool => ConversationEventVm.read(text),
    // the question itself is on the choices card (the selector leaves it
    // out); as a line it would be the model's
    TaskEventKind.question => ConversationEventVm(kind: .text, text: text),
    TaskEventKind.state => ConversationEventVm(
      kind: .state,
      text: text,
      badge: state?.badge,
    ),
    TaskEventKind.note => ConversationEventVm(kind: .note, text: text),
    TaskEventKind.error => ConversationEventVm(kind: .error, text: text),
  };
}

extension AuditEntryLine on AuditEntry {
  FoundAuditVm get line =>
      FoundAuditVm(time: time, who: who, op: op, key: key, bad: status != 0);
}

extension TaskFindingRow on TaskFinding {
  /// The row of *What I found*, marked from its node's live [quality].
  FoundRowVm row(Quality? quality) =>
      FoundRowVm(label: label, detail: detail, node: key, mark: quality.found);
}

extension TaskSuggestionTile on TaskSuggestion {
  /// The model's offer as a tile.
  SuggestionTileVm tile({
    TileNote? note,
    AgentModeVm? unattended,
    Hold? hold,
  }) => SuggestionTileVm(
    id: id,
    label: label,
    detail: detail,
    changes: changes,
    note: note,
    unattended: unattended,
    blocked: hold?.blocked,
  );
}

extension TaskQuestionView on TaskQuestion {
  /// The question on the card: answered (or the card is no longer open),
  /// one line; else its options with the [picks] made so far.
  ChoiceQuestionVm view(ISet<String> picks, {required bool open}) =>
      ChoiceQuestionVm(
        id: id,
        text: text,
        multiple: multiple,
        answer: answered || !open
            ? switch (words) {
                final w? => ChoiceAnswerVm.words(w),
                null => ChoiceAnswerVm.picked(pickedLabels),
              }
            : null,
        options: [
          for (final o in options)
            ChoiceOptionVm(
              id: o.id,
              label: o.label,
              detail: o.detail,
              picked: picks.contains(o.id),
            ),
        ],
      );
}

extension AgentTaskItem on AgentTask {
  /// The task in the left list; [own]: the user asked it.
  TaskItemVm item({required bool selected, required bool own}) => TaskItemVm(
    id: id,
    title: title,
    badge: state.badge,
    by: byOf(own: own),
    replacedBy: replacedBy,
    failedAt: failedAt,
    noChanges: noChanges,
    selected: selected,
  );

  /// The run of the plan: one row per step with what the record says of
  /// it; null before a run (a plan that waits, a rejected one).
  RunCardVm? get run {
    if (!showsRun) {
      return null;
    }
    return RunCardVm(
      badge: state.badge,
      step: step,
      leftOut: leftOut,
      kept: kept,
      seconds: ranSeconds,
      rows: [
        for (final s in plan)
          RunRowVm(
            n: s.n,
            verb: s.kind.verb,
            action: s.action,
            node: s.key,
            sleep: s.sleepSeconds,
            status: switch (s.result?.status) {
              final st? => st.run,
              null => waitOf(s).run,
            },
            answer: s.result?.message ?? '',
            ended: runEnded,
          ),
      ],
    );
  }
}

/// One plan step as the plan card shows it: [args] are the step's
/// arguments, masked where `business` masks them; [choice] its tick;
/// [revealed] whether masked arguments are shown now (null: nothing to
/// reveal); [fixes] its tiles.
PlanStepVm planStepVm(
  PlanStep s, {
  required List<ShownArg> args,
  required StepChoice? choice,
  required bool? revealed,
  required List<SuggestionTileVm> fixes,
}) => PlanStepVm(
  n: s.n,
  verb: s.kind.verb,
  action: s.action,
  node: s.key,
  sleep: s.sleepSeconds,
  level: s.level.access,
  args: [
    for (final a in args)
      switch (a.text) {
        final t? => StepArgVm.shown(a.name, t),
        null => StepArgVm.masked(a.name),
      },
    if (s.timeoutArg case final sec?) StepArgVm.timeout(sec),
  ],
  check: s.kind.changes ? s.check.view : null,
  argsNote: s.argsNote?.vm,
  revealed: revealed,
  warn: s.warn,
  modelWarn: s.modelWarn,
  fixes: fixes,
  why: s.reason,
  ticked: choice?.ticked,
  lacks: choice?.locked?.disabled,
  note: s.noteWith(choice)?.vm,
  outcome: s.result?.status.outcome,
  message: s.result?.message ?? '',
);

extension ApiKeySetState on bool? {
  /// Whether the agent's API key is set, as the rights panel draws it;
  /// null: not read yet.
  ApiKeyState get apiKey => switch (this) {
    true => ApiKeyState.set,
    false => ApiKeyState.notSet,
    null => ApiKeyState.unknown,
  };
}

/// The state read through its selectors.
final class _Read with Selectors, StateAlone {
  _Read(this.state);

  @override
  final AppState state;
}

/// One node *+ from Explorer* offers as an `@` chip.
final class ChipChoice {
  const ChipChoice({
    required this.key,
    required this.title,
    required this.icon,
    required this.selected,
  });

  final String key;

  /// Its display name, else its name.
  final String title;
  final AppIcon icon;

  /// It is Explorer's selection or point: offered first.
  final bool selected;
}

/// What *+ from Explorer* offers on the site [site].
final class ChipChoices {
  const ChipChoices({required this.site, required this.entries});

  final String site;
  final List<ChipChoice> entries;
}

/// The nodes *+ from Explorer* offers in [s] (`chipChoices`: the selection
/// first, then what Explorer read), each with its name and icon; null when
/// no chip can be added now (no site, or the chips are full).
ChipChoices? chipChoicesOf(AppState s) {
  final r = _Read(s);
  final offer = r.chipChoices;
  if (offer == null) {
    return null;
  }
  final ChipOffer(:root, :first, :rest) = offer;
  ChipChoice choice(String k, {required bool selected}) => ChipChoice(
    key: k,
    title: r.chipNameOf(k) ?? shortKey(k),
    // a key the tree has not listed (typed, or kept from a task) has no
    // decoded node: its place says what it is
    icon: nodeGlyphAt(k, root: root, info: r.nodes.table[k]).icon,
    selected: selected,
  );

  return ChipChoices(
    site: root.split('/').last,
    entries: [
      for (final k in first) choice(k, selected: true),
      for (final k in rest) choice(k, selected: false),
    ],
  );
}

/// The key [text] names when typed in the picker, and whether the agent
/// reads it (`typedChip`); null when it names none or is a chip already.
TypedChip? typedChipOf(AppState s, String text) => _Read(s).typedChip(text);
