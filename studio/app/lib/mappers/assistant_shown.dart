import 'package:business/common/memo.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/assistant_view.dart';
import 'package:business/wyrm/explorer.dart' show ExplorerTrend;
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:business/wyrm/task_facts.dart';
import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_mode.dart';
import 'package:models/audit_entry.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/found_card.dart';
import 'package:ui/assistant/more_rows_card.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/rights_panel.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/assistant/task_card.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/pages/assistant_page.dart';
import 'package:ui/theme/sizes.dart';

import '../common/trend.dart';
import 'assistant_mappers.dart';

/// Everything the Assistant draws (the tab, or the drawer over Explorer),
/// as `ui` render models: what its connector compares. Made by
/// [assistantShownOf], which keeps the last one while nothing it is made
/// of changed.
final class AssistantShown extends Equatable {
  const AssistantShown({
    required this.agent,
    required this.noAgent,
    required this.root,
    required this.sections,
    required this.title,
    required this.badge,
    required this.taskId,
    required this.planHash,
    required this.tickedSteps,
    required this.events,
    required this.plan,
    required this.choices,
    required this.run,
    required this.result,
    required this.more,
    required this.pickedRows,
    required this.stopped,
    required this.card,
    required this.second,
    required this.watch,
    required this.findingKeys,
    required this.found,
    required this.timelinePoint,
    required this.composer,
    required this.panel,
    required this.facts,
    required this.reads,
    required this.rights,
  });

  /// The agent link's key; null when the site has none.
  final String? agent;
  final bool noAgent;

  /// The root of the site on screen (`wy/<site>`), for the example a
  /// prefix dialog shows.
  final String? root;
  final IList<TaskSectionVm> sections;
  final String? title;
  final TaskBadge? badge;

  /// The task on screen.
  final String? taskId;

  /// The hash of the plan as it is shown: what Approve names.
  final String? planHash;

  /// The ticked steps of the plan as shown, in its order; null: the plan
  /// is only shown.
  final IList<int>? tickedSteps;
  final IList<ConversationEventVm> events;
  final PlanCardVm? plan;
  final ChoicesCardVm? choices;
  final RunCardVm? run;
  final ResultCardVm? result;
  final IList<MoreRowsCardVm> more;

  /// The ticked rows of *Same for more units?*; null with no task.
  final ISet<MoreRowRef>? pickedRows;
  final StoppedCardVm? stopped;
  final TaskCardVm? card;

  /// The drawer's second button: the model's tile.
  final SuggestionTileVm? second;

  /// The keys whose values the tab watches while it is shown.
  final IList<String> watch;

  /// The nodes of the findings, watched by the drawer for their marks.
  final IList<String> findingKeys;

  /// The drawer's *What I found* and mini timeline; null in the tab.
  final FoundCardVm? found;

  /// The point the drawer's timeline shows (Explorer's point).
  final String? timelinePoint;
  final ComposerVm composer;
  final AssistantTab panel;
  final TaskFactsVm? facts;
  final IList<ReadRow> reads;
  final RightsPanelVm? rights;

  @override
  List<Object?> get props => [
    agent,
    noAgent,
    root,
    sections,
    title,
    badge,
    taskId,
    planHash,
    tickedSteps,
    events,
    plan,
    choices,
    run,
    result,
    more,
    pickedRows,
    stopped,
    card,
    second,
    watch,
    findingKeys,
    found,
    timelinePoint,
    composer,
    panel,
    facts,
    reads,
    rights,
  ];
}

final _tab = Memo<AssistantShown>();
final _drawer = Memo<AssistantShown>();

/// What the Assistant draws in [s], as the tab or as the [drawer]: made
/// again only when a part of the state it reads changed
/// ([assistantInputsOf]). A dispatch elsewhere in the app, or a live value
/// of a key not on screen, gives the very same object. Nothing here reads
/// the clock.
AssistantShown assistantShownOf(AppState s, {required bool drawer}) =>
    (drawer ? _drawer : _tab).of(
      assistantInputsOf(s, drawer: drawer),
      () => _shownOf(_Read(s), drawer: drawer),
    );

/// The state read through its selectors.
final class _Read with Selectors {
  _Read(this.state);

  @override
  final AppState state;

  /// The mode under which a pick's plan may write without a person.
  AgentModeVm? get unattendedVm =>
      unattendedView(unattended, unknown: assistant.modeUnknown);
}

AssistantShown _shownOf(_Read r, {required bool drawer}) {
  final t = r.shownTask;
  final agent = r.assistant.agent;
  final choices = t == null ? null : r.choicesShown(t);
  return AssistantShown(
    agent: agent,
    noAgent: r.noAgent,
    root: r.site.root,
    sections: _sections(r),
    title: t?.title,
    badge: t?.state.badge,
    taskId: t?.id,
    planHash: t?.planHash,
    tickedSteps: choices?.tickedSteps.lock,
    events: t == null
        ? [if (r.showsNoTasks) const ConversationEventVm(kind: .noTasks)].lock
        : [for (final e in r.conversationOf(t)) e.line].lock,
    plan: t == null || !t.showsPlan ? null : _plan(r, t, choices),
    choices: t == null || !t.showsChoices ? null : _choices(r, t),
    run: t?.run,
    result: t == null || !t.showsResult ? null : _result(r, t),
    more: t == null ? const IListConst([]) : _more(r, t),
    pickedRows: t == null
        ? null
        : {
            for (final p in r.pickedRowsOf(t)) MoreRowRef(p.suggestion, p.key),
          }.lock,
    stopped: t == null ? null : _stopped(r, t),
    card: switch (t) {
      final t? => r.standingOf(t, choices)?.card(t.state.badge),
      null => null,
    },
    second: switch (t == null ? null : r.secondOf(t)) {
      SecondOffer(:final suggestion, draft: true) => suggestion.tile(
        note: .draft,
      ),
      SecondOffer(:final suggestion, :final hold) => suggestion.tile(
        note: .followUp,
        unattended: r.unattendedVm,
        hold: hold,
      ),
      null => null,
    },
    watch: r.assistantWatch.lock,
    findingKeys: r.drawerFindingKeys.lock,
    found: drawer ? _found(r, t) : null,
    timelinePoint: drawer ? r.timelinePoint : null,
    composer: _composer(r, t, drawer: drawer),
    panel: r.assistant.panel.tab,
    facts: t == null
        ? null
        : TaskFactsVm(
            taskId: t.id,
            badge: t.state.badge,
            owner: t.owner,
            events: r.sessionOf(t).length,
          ),
    reads: [for (final x in r.shownReads) ReadRow(x.tool, x.times)].lock,
    rights: r.rightsShown ? _rights(r) : null,
  );
}

/// The tasks of the list: those under way, then those that ended.
IList<TaskSectionVm> _sections(_Read r) {
  final TaskGroups(:now, :earlier) = r.taskGroups;
  TaskItemVm item(AgentTask t) => t.item(
    selected: t.id == r.tasks.selectedTask,
    own: r.askedByUser(t),
  );
  return [
    if (now.isNotEmpty)
      TaskSectionVm(section: .now, tasks: [for (final t in now) item(t)]),
    if (earlier.isNotEmpty)
      TaskSectionVm(
        section: .earlier,
        tasks: [for (final t in earlier) item(t)],
      ),
  ].lock;
}

/// The task's plan as it is approved: every step with its full key and
/// every argument (docs/agent.md: never only the model's reason).
PlanCardVm _plan(_Read r, AgentTask t, List<StepChoice>? choices) {
  final waits = t.waitsForApproval;
  return PlanCardVm(
    line: switch (r.planLineOf(t)) {
      PlanLineReplaced(:final by) => PlanReplaced(by),
      PlanLineChecked(:final checks) => PlanChecked(
        now: checks.now,
        atRun: checks.atRun,
      ),
      PlanLineApproved(:final by) => PlanApproved(by),
      PlanLineState() => PlanState(t.state.badge),
    },
    badge: t.state.badge,
    // a plan that waits is read whole; after that its run tells the story
    open: waits,
    steps: [
      for (final (i, s) in t.plan.indexed)
        planStepVm(
          s,
          args: r.argsOf(t, s),
          choice: choices?.elementAt(i),
          revealed: r.revealedShown(t, s),
          // the fixes the model offers for this step, while it waits
          fixes: [
            for (final f in t.fixesShownOf(s.n))
              f.tile(
                note: .fix,
                unattended: r.unattendedVm,
                hold: r.followHold(t),
              ),
          ],
        ),
    ],
  );
}

/// What the assistant asked: an answered question as one line, an open
/// one with its options and the picks made so far.
ChoicesCardVm _choices(_Read r, AgentTask t) {
  final open = r.answersOpen(t);
  return ChoicesCardVm(
    questions: [
      for (final q in t.questions) q.view(r.picksOf(t.id, q.id), open: open),
    ],
    confirm: r.confirmsAnswer(t),
    blocked: r.answerHold(t)?.blocked,
  );
}

/// What a finished plan left behind: the keys it touched with their
/// values now.
ResultCardVm _result(_Read r, AgentTask t) => ResultCardVm(
  facts: [
    for (final k in t.touched)
      ResultFactVm(k, switch (r.live.values[k]) {
        final v? => valueText(v.value),
        null => null,
      }),
  ],
);

/// *Same for more units?* of a task that is done: the suggestions with
/// rows, each row tickable, none ticked at first.
IList<MoreRowsCardVm> _more(_Read r, AgentTask t) => [
  for (final s in r.moreOf(t))
    MoreRowsCardVm(
      id: s.id,
      title: s.label,
      detail: s.detail,
      rows: [
        for (final row in s.rows)
          MoreRowVm(
            key: row.key,
            label: row.label,
            detail: row.detail,
            ticked: r.rowPicksOf(t.id, s.id).contains(row.key),
          ),
      ],
      blocked: r.moreHold(t, s)?.blocked,
      unattended: r.unattendedVm,
    ),
].lock;

/// Where a run stopped, what the model read about it, and its ways out.
StoppedCardVm? _stopped(_Read r, AgentTask t) => switch (t.stoppedAt) {
  final at? => StoppedCardVm(
    step: at.n,
    code: t.stopCode,
    message: t.stopMessage,
    reviewing: t.reviewing,
    review: t.review,
    // a suggestion with rows needs its ticks: the Result card has them
    ways: [for (final s in t.waysOut) s.tile(hold: r.followHold(t))],
    offered: t.suggestions.isNotEmpty,
    unattended: r.unattendedVm,
  ),
  null => null,
};

/// The ask box for the task on screen (spec `assistant.md` §4).
ComposerVm _composer(_Read r, AgentTask? t, {required bool drawer}) {
  final c = r.composerOf(t, drawer: drawer);
  return ComposerVm(
    draft: r.assistant.draft ?? '',
    hint: c.cue.hint,
    node: c.node,
    answering: c.answering,
    blocked: r.askHold?.blocked,
    chips: r.assistant.chips.toList(),
    chipBlocked: r.chipHold?.blocked,
    replaces: c.replaces,
    dense: drawer,
  );
}

/// *What it may do* (board *AssistantRights*): the modes and prefixes as
/// they will be once a staged update is applied, the model, today's
/// budget, whether the API key is set and where it goes.
RightsPanelVm _rights(_Read r) {
  final config = r.assistant.config;
  final params = r.agentParams;
  return RightsPanelVm(
    modes: [
      for (final m in ApprovalMode.values)
        ModeVm(m.view, selected: m == params.mode),
    ],
    prefixes: params.prefixes,
    agent: r.assistant.agentId,
    model: config?.model,
    used: r.budgetUsed,
    budget: config?.budgetTokensDay,
    apiKeyRef: config?.apiKeyRef,
    apiKey: r.apiKeySet.apiKey,
    sentTo: config?.sentTo,
    blocked: r.editHold?.blocked,
    staged: params.staged,
    modeUnknown: params.mode == null,
  );
}

/// *What I found* (the task's findings, each marked from its node's live
/// value) and the mini timeline of the drawer's point with the audit
/// records on it (spec assistant.md §5); null with nothing to show.
FoundCardVm? _found(_Read r, AgentTask? t) {
  if (!r.foundShown(t)) {
    return null;
  }
  final rows = [
    if (t != null)
      for (final f in r.findingsShown(t)) f.row(r.live.values[f.key]?.quality),
  ];
  final missing = [
    if (t != null)
      for (final MapEntry(:key, :value) in t.findingsRefused.entries)
        FoundMissingVm(key.view, value),
  ];
  final timeline = r.timeline;
  final audit = r.timelineAuditRead;
  return FoundCardVm(
    rows: rows,
    missing: missing,
    point: timeline == null ? null : (timeline.display ?? timeline.name),
    range: r.nodes.historyRange.code,
    timeline: timeline?.timelineVm,
    audit: [for (final a in audit ?? const IListConst<AuditEntry>([])) a.line],
    auditNote: switch (r.timelineAuditGap) {
      AuditGap.needsConfig => .needsConfig,
      AuditGap.none => .none,
      null => null,
    },
  );
}

extension on ExplorerTrend {
  /// The point's compact trend: the rows Explorer reads for it, no brush;
  /// the card adds the audit records as marks.
  TrendVm get timelineVm => TrendVm(
    title: display ?? name,
    series: [
      TrendSeriesVm(
        id: point,
        name: name,
        label: display ?? '',
        color: TrendColor.byIndex(0),
        unit: unit ?? '',
        decimals: trendDecimals(rows),
        samples: trendSamples(rows),
        overview: trendSamples(rows),
      ),
    ],
    rangeStart: span.rangeStart,
    rangeEnd: span.rangeEnd,
    windowStart: span.windowStart,
    windowEnd: span.windowEnd,
    minWindow: span.minWindow,
    endsNow: true,
    following: span.following,
    loading: loading,
    card: false,
    legend: false,
    hint: false,
    brush: false,
    plotHeight: AppSizes.timelinePlot,
    format: trendFormat(),
  );
}

extension on TaskStanding {
  /// The card under the task: what it waits for and its buttons.
  TaskCardVm card(TaskBadge badge) => switch (this) {
    StandingReplaced(:final by) => TaskCardVm(
      badge: badge,
      note: TaskNoteReplaced(by),
      buttons: [TaskButtonVm(.replacement, name: by)],
    ),
    StandingApproval(
      :final note,
      :final runs,
      :final rejectHold,
      :final approveHold,
    ) =>
      TaskCardVm(
        badge: badge,
        note: note.note,
        buttons: [
          TaskButtonVm(.reject, blocked: rejectHold?.blocked),
          TaskButtonVm(.approve, count: runs, blocked: approveHold?.blocked),
        ],
      ),
    StandingAnswer(:final cancelHold) => TaskCardVm(
      badge: badge,
      note: const TaskNoteAnswer(),
      buttons: [TaskButtonVm(.cancel, blocked: cancelHold?.blocked)],
    ),
    StandingWorking(:final cancelHold) => TaskCardVm(
      badge: badge,
      note: const TaskNoteWorking(),
      buttons: [TaskButtonVm(.cancel, blocked: cancelHold?.blocked)],
    ),
    StandingDone(
      :final task,
      :final leftOut,
      :final changedNode,
      :final trendPoint,
      :final savable,
      :final followUpHold,
    ) =>
      TaskCardVm(
        badge: badge,
        note: TaskNoteDone(leftOut),
        buttons: [
          if (changedNode != null) TaskButtonVm(.explorer, name: changedNode),
          if (trendPoint != null) TaskButtonVm(.trend, name: trendPoint),
          if (savable) const TaskButtonVm(.save),
          if (leftOut.isNotEmpty)
            TaskButtonVm(
              .followUp,
              name: task,
              steps: leftOut,
              blocked: followUpHold?.blocked,
            ),
        ],
      ),
    StandingFailed(:final error) => TaskCardVm(
      badge: badge,
      note: TaskNoteFailed(error),
    ),
  };
}
