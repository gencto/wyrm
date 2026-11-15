import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/follow_drawer_action.dart';
import 'package:business/redux/assistant/actions/pick_suggestion_action.dart';
import 'package:business/redux/assistant/actions/send_ask_action.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/assistant/actions/set_option_pick_action.dart';
import 'package:business/redux/assistant/actions/set_panel_action.dart';
import 'package:business/redux/assistant/actions/set_row_pick_action.dart';
import 'package:business/redux/assistant/actions/set_step_reveal_action.dart';
import 'package:business/redux/assistant/actions/set_step_tick_action.dart';
import 'package:business/redux/assistant/actions/set_watched_action.dart';
import 'package:business/redux/assistant/actions/show_assistant_action.dart';
import 'package:business/redux/assistant/actions/show_drawer_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/nodes/actions/open_trend_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/set_history_window_action.dart';
import 'package:business/redux/tasks/actions/answer_task_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/new_task_action.dart';
import 'package:business/redux/tasks/actions/open_task_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/history_steps.dart';
import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:business/wyrm/task_facts.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_mode.dart';
import 'package:models/assistant_panel.dart';
import 'package:models/audit_entry.dart';
import 'package:models/hist_point.dart';
import 'package:models/task_state.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/assistant_drawer.dart';
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
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/assistant_page.dart';

import '../common/tab_visibility.dart';
import '../common/trend.dart';
import '../dialogs/assistant_dialogs.dart';
import '../mappers/assistant_mappers.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';
import '../navigation/go_after_action.dart';

/// The Assistant tab (spec `assistant.md`): the agent's tasks, the selected
/// task's conversation and cards, the ask box, *This task* and *What it may
/// do*. It reads selectors (`AssistantScreen`, `TaskFacts`), maps the
/// domain through `app/lib/mappers/assistant_mappers.dart`, passes typed
/// values (the widgets word them) and starts one action per intent; a
/// control that asks first opens its dialog from `assistant_dialogs.dart`.
@RoutePage()
class AssistantPageConnector extends StatelessWidget {
  const AssistantPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    // the keys the Result card shows, watched while the tab is shown
    onWillChange: (context, store, before, now) {
      if (store.state.assistant.shown && !_same(before.watch, now.watch)) {
        store.dispatchSync(SetWatchedAction(now.watch.lock));
      }
    },
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: AssistantPage(
        sections: vm.sections,
        onNew: vm.onNew,
        onTask: vm.onTask,
        agent: vm.agent,
        noAgent: vm.noAgent,
        title: vm.title,
        badge: vm.badge,
        taskId: vm.taskId,
        events: vm.events,
        plan: vm.plan,
        onTick: vm.ticks?.onToggle,
        onFix: vm.onPickSuggestion,
        onReveal: vm.onReveal,
        run: vm.run,
        result: vm.result,
        more: vm.more,
        onRow: vm.rows?.onToggle,
        onMore: vm.onPickSuggestion,
        stopped: vm.stopped,
        onWay: vm.onPickSuggestion,
        choices: vm.choices,
        onPick: switch (vm.onPick) {
          final pick? => (q, o) => pick((question: q, option: o)),
          null => null,
        },
        onAnswer: vm.onAnswer,
        card: vm.card,
        // a control that asks first opens its dialog; the others start
        // their action at once
        onButton: (b) => pressTaskButton(context, b, vm.buttons),
        composer: vm.composer,
        onDraft: vm.onDraft,
        onAsk: vm.onAsk,
        onChipRemove: vm.onChipRemove,
        onAddChip: () => pickContextKey(context),
        panel: vm.panel,
        onPanel: vm.onPanel,
        facts: vm.facts,
        reads: vm.reads,
        rights: vm.rights,
        onMode: vm.onMode,
        onRemovePrefix: vm.onRemovePrefix,
        onAddPrefix: () => addPrefix(context),
        onAddAgent: vm.onAddAgent,
      ),
    ),
  );
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length && a.every(b.contains);

/// The Assistant as a drawer over Explorer (⌘J, spec `assistant.md` §5):
/// the same task and cards as the tab, from the same view-model.
class AssistantDrawerConnector extends StatelessWidget {
  const AssistantDrawerConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this, drawer: true),
    // the selected point's timeline
    onInitialBuild: (context, store, vm) =>
        store.dispatch(FollowDrawerAction()),
    // the finding nodes, watched while the drawer is shown, and the
    // timeline of Explorer's point
    onWillChange: (context, store, before, now) =>
        !_same(before.findingKeys, now.findingKeys) ||
            before.timelinePoint != now.timelinePoint
        ? store.dispatch(FollowDrawerAction())
        : null,
    // the drawer is in Explorer's page: shown while Explorer's tab is the
    // active one and the drawer is open (ADR 0037 rule 5)
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: AssistantDrawer(
        taskId: vm.taskId,
        onOpenFull: vm.onOpenFull,
        onClose: vm.onCloseDrawer,
        events: vm.events,
        choices: vm.choices,
        onPick: switch (vm.onPick) {
          final pick? => (q, o) => pick((question: q, option: o)),
          null => null,
        },
        onAnswer: vm.onAnswer,
        plan: vm.plan,
        onTick: vm.ticks?.onToggle,
        onFix: vm.onPickSuggestion,
        onReveal: vm.onReveal,
        run: vm.run,
        stopped: vm.stopped,
        onWay: vm.onPickSuggestion,
        card: vm.card,
        second: vm.second,
        onSecond: () async {
          // while the plan waits the tile is a draft the person copies
          // (spec §5); after the task it is a follow-up ask
          if (vm.second case final s?) {
            if (s.note == TileNote.draft) {
              await copyDraft(context, label: s.label, detail: s.detail);
            } else {
              vm.onPickSuggestion?.call(s.id);
            }
          }
        },
        onNewTask: vm.onNewTask,
        onButton: (b) => pressTaskButton(context, b, vm.buttons),
        noAgent: vm.noAgent,
        found: vm.found,
        onTimelineWindow: (a, b) => vm.onTimelineWindow((start: a, end: b)),
        onTimelineReset: vm.onTimelineReset,
        composer: AssistantComposer(
          vm: vm.composer,
          onDraft: vm.onDraft,
          onAsk: vm.onAsk,
          onChipRemove: vm.onChipRemove,
          onAddChip: () => pickContextKey(context),
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector (of the tab
/// and, with [drawer], of the drawer).
class _Factory extends VmFactory<AppState, StatelessWidget, _Vm>
    with Selectors {
  _Factory(super._connector, {this.drawer = false});

  final bool drawer;

  @override
  _Vm fromStore() {
    final agent = assistant.agent;
    final t = shownTask;
    final id = t?.id;
    final choices = t == null ? null : choicesShown(t);
    final rights = assistant.panel == AssistantPanel.rights;
    return _Vm(
      agent: agent,
      noAgent: agent == null && !assistant.isWaiting && !links.isWaiting,
      sections: _sections(),
      title: t?.title,
      badge: t?.state.badge,
      taskId: id,
      events: t == null
          ? [if (agent != null) const ConversationEventVm(kind: .noTasks)]
          : [for (final e in conversationOf(t)) e.line],
      plan: t == null || t.plan.isEmpty ? null : _plan(t, choices),
      ticks: id == null || choices == null
          ? null
          : ToggleVm(
              selected: choices.tickedSteps.toISet(),
              onToggle: (n, {required on}) =>
                  dispatchSync(SetStepTickAction(id, n, ticked: on)),
            ),
      choices: t == null || t.questions.isEmpty ? null : _choices(t),
      onPick: id == null
          ? null
          : (p) => dispatchSync(
              SetOptionPickAction.of(id, p.question, p.option),
            ),
      onAnswer: id == null ? null : () => dispatch(AnswerTaskAction(id)),
      run: t?.run,
      result: t == null ? null : _result(t),
      more: t == null ? const [] : _more(t),
      stopped: t == null ? null : _stopped(t),
      card: t == null ? null : _card(t, choices),
      second: t == null ? null : _second(t),
      onPickSuggestion: id == null
          ? null
          : (s) => dispatch(PickSuggestionAction(id, s)),
      rows: t == null
          ? null
          : ToggleVm(
              selected: pickedRowsOf(t),
              onToggle: (row, {required on}) => dispatchSync(
                SetRowPickAction(t.id, row.suggestion, row.key, on: on),
              ),
            ),
      onReveal: id == null
          ? null
          : (n) => dispatchSync(SetStepRevealAction.toggle(id, n)),
      buttons: TaskButtonActions(
        task: id,
        // what is on screen now: the plan and the ticks as shown
        approve: t == null
            ? null
            : () => dispatch(
                ApproveTaskAction(
                  t.id,
                  plan: t.planHash,
                  steps: (choices ?? const <StepChoice>[]).tickedSteps,
                ),
              ),
        replacement: switch (t?.replacedBy) {
          final next? => () => dispatch(OpenTaskAction(next)),
          null => null,
        },
        explorer: switch (t?.changedNode) {
          final node? => () => dispatch(
            GoAfterAction(const ExplorerRoute(), [SelectNodeAction(node)]),
          ),
          null => null,
        },
        trend: switch (t?.touched.lastOrNull) {
          final key? => () => dispatch(
            GoAfterAction(const ExplorerRoute(), [
              SetDrawerAction(open: false),
              OpenTrendAction(key),
            ]),
          ),
          null => null,
        },
        followUp: id == null
            ? null
            : (text) => dispatch(AskAgentAction(text: text, parent: id)),
      ),
      watch: assistantWatch,
      findingKeys: drawerFindingKeys,
      found: assistant.drawer ? _found(t) : null,
      timelinePoint: assistant.drawer ? timelinePoint : null,
      onTimelineWindow: (w) {
        final (start, end) = _historyRange(nodes.historyKey);
        dispatchSync(
          SetHistoryWindowAction(trendWindow(w.start, w.end, start, end)),
        );
      },
      onTimelineReset: () => dispatchSync(SetHistoryWindowAction(null)),
      composer: _composer(t),
      onDraft: (text) => dispatchSync(SetDraftAction(text)),
      onAsk: () => dispatch(SendAskAction(drawer: drawer)),
      onChipRemove: (k) => dispatchSync(SetChipAction(k, on: false)),
      panel: assistant.panel.tab,
      onPanel: (p) => dispatch(SetPanelAction(p.panel)),
      facts: t == null
          ? null
          : TaskFactsVm(
              taskId: t.id,
              badge: t.state.badge,
              owner: t.owner,
              events: sessionOf(t).length,
            ),
      reads: rights || t == null ? const [] : readsOf(t),
      rights: rights ? _rights() : null,
      onMode: (m) => dispatch(StageAgentParamAction.mode(m.domain)),
      onRemovePrefix: (p) => dispatch(StageAgentParamAction.removePrefix(p)),
      onAddAgent: () => dispatch(GoAction.push(const LinkInstallRoute())),
      onShow: () => dispatch(
        drawer
            ? ShowDrawerAction(shown: true)
            : ShowAssistantAction(shown: true),
      ),
      onHide: () => dispatch(
        drawer
            ? ShowDrawerAction(shown: false)
            : ShowAssistantAction(shown: false),
      ),
      onNew: () => dispatchSync(NewTaskAction()),
      onNewTask: id == null
          ? null
          : () => dispatchSync(SetSelectedTaskAction(null)),
      onTask: (task) => dispatch(OpenTaskAction(task)),
      onOpenFull: id == null
          ? null
          : () => dispatch(
              GoAfterAction(const AssistantRoute(), [
                SetDrawerAction(open: false),
              ]),
            ),
      onCloseDrawer: () => dispatchSync(SetDrawerAction(open: false)),
    );
  }

  List<TaskSectionVm> _sections() {
    final (:now, :earlier) = taskGroups;
    TaskItemVm item(AgentTask t) =>
        t.item(selected: t.id == tasks.selectedTask, own: askedByUser(t));
    return [
      if (now.isNotEmpty)
        TaskSectionVm(section: .now, tasks: [for (final t in now) item(t)]),
      if (earlier.isNotEmpty)
        TaskSectionVm(
          section: .earlier,
          tasks: [for (final t in earlier) item(t)],
        ),
    ];
  }

  /// The task's plan as it is approved: every step with its full key and
  /// every argument (docs/agent.md: never only the model's reason).
  PlanCardVm _plan(AgentTask t, List<StepChoice>? choices) {
    final waits = t.state == TaskState.awaitingApproval && t.replacedBy == null;
    return PlanCardVm(
      line: switch (t.replacedBy) {
        final next? => PlanReplaced(next),
        null when t.state == TaskState.awaitingApproval => switch (planChecks(
          t.plan,
        )) {
          (:final now, :final atRun) => PlanChecked(now: now, atRun: atRun),
        },
        null => switch (t.approvedBy) {
          final line? => PlanApproved(line),
          null => PlanState(t.state.badge),
        },
      },
      badge: t.state.badge,
      // a plan that waits is read whole; after that its run tells the story
      open: waits,
      steps: [
        for (final (i, s) in t.plan.indexed)
          planStepVm(
            s,
            args: argsOf(t, s),
            choice: choices?.elementAt(i),
            revealed: revealedOf(t.id, s.n),
            // the fixes the model offers for this step, while it waits
            fixes: waits
                ? [
                    for (final f in t.fixesOf(s.n))
                      f.tile(
                        note: .fix,
                        unattended: unattended,
                        hold: followHold(t),
                      ),
                  ]
                : const [],
          ),
      ],
    );
  }

  /// What the assistant asked: an answered question as one line, an open
  /// one with its options and the picks made so far.
  ChoicesCardVm _choices(AgentTask t) {
    final open = t.state == TaskState.awaitingAnswer;
    return ChoicesCardVm(
      questions: [
        for (final q in t.questions) q.view(picksOf(t.id, q.id), open: open),
      ],
      confirm: open && t.questions.any((q) => !q.answered),
      blocked: answerHold(t)?.blocked,
    );
  }

  /// What a finished plan left behind: the keys it touched with their
  /// values now.
  ResultCardVm? _result(AgentTask t) {
    final keys = t.touched;
    return keys.isEmpty
        ? null
        : ResultCardVm(
            facts: [
              for (final k in keys) (key: k, value: _valueOf(k)),
            ],
          );
  }

  String? _valueOf(String key) => switch (live.values[key]) {
    final v? => valueText(v.value),
    null => null,
  };

  /// *Same for more units?* of a task that is done: the suggestions with
  /// rows, each row tickable, none ticked at first.
  List<MoreRowsCardVm> _more(AgentTask t) => t.state != TaskState.done
      ? const []
      : [
          for (final s in t.withRows)
            MoreRowsCardVm(
              id: s.id,
              title: s.label,
              detail: s.detail,
              rows: [
                for (final r in s.rows)
                  MoreRowVm(
                    key: r.key,
                    label: r.label,
                    detail: r.detail,
                    ticked: rowPicksOf(t.id, s.id).contains(r.key),
                  ),
              ],
              blocked: moreHold(t, s)?.blocked,
              unattended: unattended?.view,
            ),
        ];

  /// Where a run stopped, what the model read about it, and its ways out.
  StoppedCardVm? _stopped(AgentTask t) {
    final at = t.failedStep;
    if (t.state != TaskState.failed || t.replacedBy != null || at == null) {
      return null;
    }
    return StoppedCardVm(
      step: at.n,
      code: t.stopCode,
      message: t.stopMessage,
      reviewing: t.reviewing,
      review: t.review,
      // a suggestion with rows needs its ticks: the Result card has them
      ways: [for (final s in t.waysOut) s.tile(hold: followHold(t))],
      offered: t.suggestions.isNotEmpty,
      unattended: unattended?.view,
    );
  }

  /// The card under the task: what it waits for and its buttons.
  TaskCardVm? _card(AgentTask t, List<StepChoice>? choices) {
    final badge = t.state.badge;
    final cancel = TaskButtonVm(.cancel, blocked: writeHold?.blocked);
    // a plan another task took the place of: never approved, and the way
    // to the task that replaced it (its `~val` may still say it waits)
    if (t.replacedBy case final next?) {
      return TaskCardVm(
        badge: badge,
        note: TaskNoteReplaced(next),
        buttons: [TaskButtonVm(.replacement, name: next)],
      );
    }
    return switch (t.state) {
      TaskState.awaitingApproval => _approval(t, choices ?? const []),
      TaskState.awaitingAnswer => TaskCardVm(
        badge: badge,
        note: const TaskNoteAnswer(),
        buttons: [cancel],
      ),
      TaskState.planning || TaskState.running => TaskCardVm(
        badge: badge,
        note: const TaskNoteWorking(),
        buttons: [cancel],
      ),
      TaskState.done => TaskCardVm(
        badge: badge,
        note: TaskNoteDone(t.leftOut),
        buttons: [
          if (t.changedNode case final node?)
            TaskButtonVm(.explorer, name: node),
          if (t.touched.lastOrNull case final key?)
            TaskButtonVm(.trend, name: key),
          if (t.plan.isNotEmpty) const TaskButtonVm(.save),
          if (t.leftOut case final left when left.isNotEmpty)
            TaskButtonVm(
              .followUp,
              name: t.id,
              steps: left,
              blocked: followUpHold?.blocked,
            ),
        ],
      ),
      // stopped in its run: the Stopped card says where and what next;
      // while the model reviews the run it can be cancelled
      TaskState.failed => switch (t.failedStep) {
        _? when t.reviewing => TaskCardVm(
          badge: badge,
          note: const TaskNoteWorking(),
          buttons: [cancel],
        ),
        _? => null,
        null => TaskCardVm(badge: badge, note: TaskNoteFailed(t.error)),
      },
    };
  }

  /// The card of a plan that waits: what Approve signs, Reject, Approve.
  TaskCardVm _approval(AgentTask t, List<StepChoice> choices) {
    final ticked = choices.where((c) => c.ticked ?? false).length;
    // every change that runs once approved: the ticked steps, and those
    // the agent runs with its own key (no tick, cannot be left out)
    final runs = choices.where((c) => c.runs).length;
    final byAgent = choices.where((c) => c.byAgent && !c.skipped).length;
    final refusal = assistant.refusals[t.id];
    return TaskCardVm(
      badge: t.state.badge,
      note: !assistant.docs
          // a gateway older than `doc` cannot show the plan
          ? const TaskNoteNoRecord()
          : otherSite != null
          ? TaskNoteOtherSite(otherSite!)
          // the task keeps waiting: what was refused, and the way on
          : refusal != null
          ? TaskNoteRefused(refusal)
          : !t.recorded
          ? const TaskNoteWaiting()
          : TaskNoteSigns(role: site.role ?? '', byAgent: byAgent),
      buttons: [
        TaskButtonVm(.reject, blocked: writeHold?.blocked),
        TaskButtonVm(
          .approve,
          count: ticked == 0 ? 0 : runs,
          blocked: approveHold(t, choices)?.blocked,
        ),
      ],
    );
  }

  /// The drawer's second button as the model's tile (spec §5): while the
  /// plan waits a draft to copy (an ask would replace a plan the person
  /// may still approve); after a done task a follow-up ask.
  SuggestionTileVm? _second(AgentTask t) {
    final s = t.second;
    final waits = t.state == TaskState.awaitingApproval;
    if (s == null ||
        t.replacedBy != null ||
        (!waits && t.state != TaskState.done)) {
      return null;
    }
    return waits
        ? s.tile(note: .draft)
        : s.tile(note: .followUp, unattended: unattended, hold: followHold(t));
  }

  /// The ask box for the task on screen (spec `assistant.md` §4).
  ComposerVm _composer(AgentTask? t) {
    final answering = t?.state == TaskState.awaitingAnswer;
    return ComposerVm(
      draft: assistant.draft ?? '',
      hint: drawer && !answering
          ? .drawer
          : (t?.hint(follows: askParent(t) != null) ?? .ask),
      node: t?.failedStep?.key ?? '',
      answering: answering,
      blocked: askHold?.blocked,
      chips: assistant.chips.toList(),
      chipBlocked: chipHold?.blocked,
      replaces: !drawer && t != null && replacesPlan(t),
      dense: drawer,
    );
  }

  /// *What it may do* (board *AssistantRights*): the modes and prefixes as
  /// they will be once a staged update is applied, the model, today's
  /// budget, whether the API key is set and where it goes.
  RightsPanelVm _rights() {
    final config = assistant.config;
    final params = agentParams;
    return RightsPanelVm(
      modes: [
        for (final m in ApprovalMode.values)
          ModeVm(m.view, selected: m == params.mode),
      ],
      prefixes: params.prefixes,
      agent: assistant.agentId,
      model: config?.model,
      used: budgetUsed,
      budget: config?.budgetTokensDay,
      apiKeyRef: config?.apiKeyRef,
      apiKey: switch (apiKeySet) {
        true => .set,
        false => .notSet,
        null => .unknown,
      },
      sentTo: config?.sentTo,
      blocked: editHold?.blocked,
      staged: params.staged,
    );
  }

  /// *What I found* (the task's findings, each marked from its node's live
  /// value) and the mini timeline of the drawer's point with the audit
  /// records on it (spec assistant.md §5).
  FoundCardVm? _found(AgentTask? t) {
    final rows = [
      if (t != null)
        for (final f in findingsShown(t)) f.row(live.values[f.key]?.quality),
    ];
    final missing = [
      if (t != null)
        for (final MapEntry(:key, :value) in t.findingsRefused.entries)
          FoundMissingVm(key.view, value),
    ];
    final point = timelinePoint;
    if (rows.isEmpty && missing.isEmpty && point == null) {
      return null;
    }
    final read = assistant.timelineKey == point;
    final audit = read
        ? assistant.timelineAudit
        : const IListConst<AuditEntry>([]);
    return FoundCardVm(
      rows: rows,
      missing: missing,
      point: point == null
          ? null
          : (nodes.table[point]?.display ?? lastSegment(point)),
      range: nodes.historyRange,
      timeline: point == null ? null : _timeline(point),
      audit: [for (final a in audit) a.line],
      auditNote: !site.can('config', '${site.root ?? ''}/sys/audit')
          ? .needsConfig
          : read && audit.isEmpty
          ? .none
          : null,
    );
  }

  /// The range of the history read for [key] in µs (as Explorer's).
  (int, int) _historyRange(String? key) {
    final span = RetrieveHistoryAction.span(nodes.historyRange);
    final rows = nodes.historyKey == key && key != null
        ? nodes.history
        : const IListConst<HistPoint>([]);
    final e = trendRangeEnd(nodes.historyAt, [rows.lastOrNull?.time]);
    return (e - span.inMicroseconds, e);
  }

  /// The point's compact trend: the rows Explorer reads for it, no brush;
  /// the card adds the audit records as marks.
  TrendVm _timeline(String point) {
    final (rs, re) = _historyRange(point);
    final w = nodes.historyWindow;
    final we = w?.end?.microsecondsSinceEpoch ?? re;
    final ws = w == null ? rs : we - w.span.inMicroseconds;
    final span = RetrieveHistoryAction.span(nodes.historyRange);
    final read = nodes.historyKey == point;
    final rows = read ? nodes.history : const IListConst<HistPoint>([]);
    final info = nodes.table[point];
    return TrendVm(
      title: info?.display ?? lastSegment(point),
      series: [
        TrendSeriesVm(
          id: point,
          name: lastSegment(point),
          label: info?.display ?? '',
          color: TrendColor.byIndex(0),
          unit: info?.unit ?? '',
          decimals: trendDecimals(rows),
          samples: trendSamples(rows),
          overview: trendSamples(rows),
        ),
      ],
      rangeStart: rs,
      rangeEnd: re,
      windowStart: ws.clamp(rs, re),
      windowEnd: we.clamp(rs, re),
      rollup: rollupText(null),
      minWindow: 12 * stepDuration(stepFor(span, raw: false))!.inMicroseconds,
      endsNow: true,
      following: w?.end == null,
      loading: !read || (rows.isEmpty && nodes.historyLoading),
      card: false,
      legend: false,
      hint: false,
      brush: false,
      plotHeight: 64,
      format: trendFormat(),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.agent,
    required this.noAgent,
    required this.sections,
    required this.title,
    required this.badge,
    required this.taskId,
    required this.events,
    required this.plan,
    required this.ticks,
    required this.choices,
    required this.onPick,
    required this.onAnswer,
    required this.run,
    required this.result,
    required this.more,
    required this.stopped,
    required this.card,
    required this.second,
    required this.onPickSuggestion,
    required this.rows,
    required this.onReveal,
    required this.buttons,
    required this.watch,
    required this.findingKeys,
    required this.found,
    required this.timelinePoint,
    required this.onTimelineWindow,
    required this.onTimelineReset,
    required this.composer,
    required this.onDraft,
    required this.onAsk,
    required this.onChipRemove,
    required this.panel,
    required this.onPanel,
    required this.facts,
    required this.reads,
    required this.rights,
    required this.onMode,
    required this.onRemovePrefix,
    required this.onAddAgent,
    required this.onShow,
    required this.onHide,
    required this.onNew,
    required this.onNewTask,
    required this.onTask,
    required this.onOpenFull,
    required this.onCloseDrawer,
  }) : super(
         equals: [
           agent,
           noAgent,
           sections,
           title,
           badge,
           taskId,
           events,
           plan,
           ticks,
           choices,
           run,
           result,
           more,
           rows,
           stopped,
           card,
           buttons,
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
           onNewTask != null,
           onOpenFull != null,
         ],
       );

  final String? agent;
  final bool noAgent;
  final List<TaskSectionVm> sections;
  final String? title;
  final TaskBadge? badge;
  final String? taskId;
  final List<ConversationEventVm> events;
  final PlanCardVm? plan;

  /// The ticks of the plan; null: the plan is only shown.
  final ToggleVm<int>? ticks;
  final ChoicesCardVm? choices;

  /// An option of a question was picked.
  final ValueChanged<({String question, String option})>? onPick;
  final VoidCallback? onAnswer;
  final RunCardVm? run;
  final ResultCardVm? result;
  final List<MoreRowsCardVm> more;
  final StoppedCardVm? stopped;
  final TaskCardVm? card;

  /// The drawer's second button: the model's tile.
  final SuggestionTileVm? second;

  /// A suggestion (a fix, a way out, more units) of the task was picked.
  final ValueChanged<String>? onPickSuggestion;

  /// The ticked rows of *Same for more units?*.
  final ToggleVm<MoreRowRef>? rows;
  final ValueChanged<int>? onReveal;

  /// What the card's buttons that start their action at once do.
  final TaskButtonActions buttons;

  /// The keys whose values the Result card shows.
  final List<String> watch;

  /// The nodes of the findings, watched by the drawer for their marks.
  final List<String> findingKeys;

  /// The drawer's *What I found* and mini timeline; null when closed.
  final FoundCardVm? found;

  /// The point the drawer's timeline shows (the Explorer point).
  final String? timelinePoint;
  final ValueChanged<({int start, int end})> onTimelineWindow;
  final VoidCallback onTimelineReset;
  final ComposerVm composer;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final ValueChanged<String> onChipRemove;
  final AssistantTab panel;
  final ValueChanged<AssistantTab> onPanel;
  final TaskFactsVm? facts;
  final List<ReadRow> reads;
  final RightsPanelVm? rights;
  final ValueChanged<AgentModeVm> onMode;
  final ValueChanged<String> onRemovePrefix;
  final VoidCallback onAddAgent;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onNew;
  final VoidCallback? onNewTask;
  final ValueChanged<String> onTask;
  final VoidCallback? onOpenFull;
  final VoidCallback onCloseDrawer;
}
