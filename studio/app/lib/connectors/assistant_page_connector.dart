import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/load_assistant_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_panel_action.dart';
import 'package:business/redux/assistant/actions/set_shown_action.dart';
import 'package:business/redux/assistant/actions/set_step_tick_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/labels.dart';
import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/task_event.dart';
import 'package:models/task_state.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/reason_dialog.dart';
import 'package:ui/pages/assistant_page.dart';

import '../common/tab_visibility.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// What a secret argument of a plan step is shown as.
const secretMask = '••••••';

@RoutePage()
class AssistantPageConnector extends StatelessWidget {
  const AssistantPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: AssistantPage(
        newLabel: S.current.newTask,
        listNote: S.current.taskListNote(vm.agentName),
        sections: vm.sections,
        onNew: vm.onNew,
        onTask: vm.onTask,
        title: vm.title,
        status: vm.status,
        taskKey: vm.taskKey,
        events: vm.events,
        plan: vm.plan,
        onTick: vm.onTick,
        card: vm.card,
        onButton: (b) => vm.onButton(context, b),
        draft: vm.draft,
        askHint: S.current.askHint,
        askLabel: S.current.askButton,
        askReason: vm.askReason,
        onDraft: vm.onDraft,
        onAsk: vm.onAsk,
        panels: [
          TabItemVm(id: 'task', label: S.current.panelThisTask),
          TabItemVm(id: 'rights', label: S.current.panelMayDo),
        ],
        panel: vm.panel,
        onPanel: vm.onPanel,
        facts: vm.facts,
        readsLabel: S.current.whatItRead,
        reads: vm.reads,
        panelNote: vm.panelNote,
        empty: vm.empty,
        emptyAction: vm.empty == null ? null : S.current.addAgent,
        onEmptyAction: vm.onAddAgent,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, AssistantPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final agent = assistant.agent;
    final id = tasks.selectedTask;
    final task = id == null ? null : tasks.table[id];
    final events = id == null
        ? const <TaskEvent>[]
        : (tasks.events[id]?.toList() ?? const <TaskEvent>[]);
    final reads = <String, int>{};
    for (final e in events) {
      if (e.kind == 'tool') {
        reads[e.text] = (reads[e.text] ?? 0) + 1;
      }
    }
    final rights = assistant.panel == 'rights';
    final cancelReason = agent == null ? null : site.needs('write', agent);
    // the ticks of a plan that waits; none where this gateway cannot sign
    final choices =
        task != null && task.state == .awaitingApproval && otherSite == null
        ? choicesOf(task)
        : null;
    return _Vm(
      agentName: agent?.split('/').skip(2).join('/') ?? 'agent',
      sections: _sections(id),
      title: task == null ? null : _title(task),
      status: task == null
          ? null
          : StatusPillVm(
              label: _stateLabel(task.state),
              tone: _tone(task.state),
            ),
      taskKey: task == null ? null : 'tasks/${task.id}',
      events: task == null
          ? [
              if (agent != null)
                ConversationEventVm(kind: .text, text: S.current.noTasks),
            ]
          : _conversation(events.isEmpty ? _fromLog(task) : events),
      plan: task == null || task.plan.isEmpty ? null : _plan(task, choices),
      onTick: id == null || choices == null
          ? null
          : (n, {required ticked}) =>
                dispatchSync(SetStepTickAction(id, n, ticked: ticked)),
      card: task == null ? null : _card(task, cancelReason, choices),
      draft: assistant.draft ?? '',
      askReason: agent == null
          ? S.current.noAgent
          : (site.needs('write', agent) ?? (_asking ? '…' : null)),
      panel: assistant.panel,
      facts: rights
          ? [
              if (agent != null)
                FactVm(
                  label: S.current.factAgent,
                  value: agent.split('/').skip(2).join('/'),
                  mono: true,
                ),
              for (final k in shownCfg)
                if (assistant.cfg[k] case final v?)
                  FactVm(label: _cfgLabel(k), value: v, mono: true),
            ]
          : [
              if (task != null) ...[
                FactVm(
                  label: S.current.factTask,
                  value: 'tasks/${task.id}',
                  mono: true,
                ),
                FactVm(
                  label: S.current.factTaskState,
                  value: _stateLabel(task.state),
                ),
                if (task.owner.isNotEmpty)
                  FactVm(label: S.current.factAskedBy, value: task.owner),
                if (events.isNotEmpty)
                  FactVm(
                    label: S.current.factEvents,
                    value: '${events.length}',
                  ),
              ],
            ],
      reads: rights
          ? const []
          : [
              for (final MapEntry(:key, :value) in reads.entries)
                (key, value > 1 ? '× $value' : ''),
            ],
      panelNote: rights
          ? S.current.mayDoNote
          : (reads.isEmpty ? '' : S.current.readsNote),
      empty: agent == null && !_loading ? S.current.noAgent : null,
      onShow: () {
        dispatchSync(SetShownAction(true));
        unawaited(dispatchAndWait(LoadAssistantAction()));
      },
      onHide: () => dispatchSync(SetShownAction(false)),
      onNew: () {
        dispatchSync(SetSelectedTaskAction(null));
        dispatchSync(SetPanelAction('task'));
      },
      onTask: (t) {
        dispatchSync(SetSelectedTaskAction(t));
        unawaited(dispatchAndWait(RetrieveTaskRecordAction(t)));
      },
      onDraft: (t) => dispatchSync(SetDraftAction(t)),
      onAsk: () => unawaited(dispatchAndWait(AskAgentAction())),
      onPanel: (p) => dispatchSync(SetPanelAction(p)),
      onAddAgent: () => dispatchSync(GoAction.push(const LinkInstallRoute())),
      onButton: (context, b) async {
        if (id == null) {
          return;
        }
        switch (b) {
          case 'approve':
            // what is on screen now: the plan and the ticks as shown
            await dispatchAndWait(
              ApproveTaskAction(
                id,
                plan: task?.planHash,
                steps: [
                  for (final c in choices ?? const <StepChoice>[])
                    if (c.ticked ?? false) c.n,
                ],
              ),
            );
          case 'reject':
            final reason = await ReasonDialog.ask(
              context,
              title: S.current.rejectPlanTitle,
              message: S.current.rejectPlanNote,
              hint: S.current.rejectPlanHint,
              confirm: S.current.reject,
              cancel: S.current.cancel,
            );
            if (reason != null) {
              await dispatchAndWait(RejectTaskAction(id, reason: reason));
            }
          case 'followup':
            final left = _leftOut(task);
            if (left.isNotEmpty) {
              await dispatchAndWait(
                AskAgentAction(
                  text: S.current.followUpAsk(id, left.join(', ')),
                  parent: id,
                ),
              );
            }
          case 'cancel':
            if (await ConfirmDialog.ask(
              context,
              title: S.current.cancelTask,
              message: S.current.failedNote,
              confirm: S.current.cancelTask,
              cancel: S.current.cancel,
            )) {
              await dispatchAndWait(CancelTaskAction(id));
            }
        }
      },
    );
  }

  bool get _asking => assistant.isAsking;

  bool get _approving => assistant.isApproving;

  bool get _loading => assistant.isWaiting || links.isWaiting;

  /// The conversation of a task asked in another session, from its record:
  /// the ask, then the log (`model: …` lines as the model's, `proposed …`
  /// and the like as what it did, `failed: …` as the error).
  static List<TaskEvent> _fromLog(AgentTask t) => [
    if (t.ask.isNotEmpty) TaskEvent(kind: 'ask', text: t.ask),
    for (final l in t.log)
      if (l.startsWith('model: '))
        TaskEvent(kind: 'text', text: l.substring(7))
      else if (l.startsWith('failed: '))
        TaskEvent(kind: 'error', text: l.substring(8))
      else if (!l.startsWith('asked by '))
        TaskEvent(kind: 'note', text: l),
  ];

  /// The task's plan as it is approved: every step with its full key and
  /// every argument (docs/agent.md: never only the model's reason).
  PlanCardVm _plan(AgentTask t, List<StepChoice>? choices) => PlanCardVm(
    title: S.current.planSteps(t.plan.length),
    state: t.state == .awaitingApproval
        ? switch (planChecks(t.plan)) {
            (now: _, atRun: 0) => S.current.planChecked,
            (:final now, :final atRun) => S.current.planCheckedPartly(
              now,
              atRun,
            ),
          }
        : (_approvedBy(t) ?? _stateLabel(t.state)),
    stateTone: _tone(t.state),
    note: S.current.planWhyNote,
    steps: [
      for (final (i, s) in t.plan.indexed) _step(s, choices?.elementAt(i)),
    ],
  );

  /// `approved by olena, 1 step(s) left out`: the record's own line.
  static String? _approvedBy(AgentTask t) => t.log
      .where((l) => l.startsWith('approved by '))
      .map((l) => l.replaceFirst('approved by user:', 'approved by '))
      .lastOrNull;

  /// The numbers of the steps a run left out.
  static List<int> _leftOut(AgentTask? t) => [
    for (final s in t?.plan ?? const IListConst<PlanStep>([]))
      if (s.result?.status == 'skipped') s.n,
  ];

  static PlanStepVm _step(PlanStep s, StepChoice? choice) {
    final changes = s.op == 'set' || s.op == 'invoke';
    return PlanStepVm(
      n: s.n,
      verb: s.op.toUpperCase(),
      action: s.action,
      target: s.op == 'sleep'
          ? S.current.planSleep(_num(s.seconds ?? 0))
          : s.key,
      level: s.level,
      changes: changes,
      args: [
        for (final e in s.args.entries)
          (
            e.key,
            // a secret is not shown; the approval is still bound to it
            s.secret.contains(e.key) ? secretMask : _shown(e.value),
          ),
        if (s.op != 'sleep')
          if (s.seconds case final sec?)
            ('timeout', S.current.planSleep(_num(sec))),
      ],
      check: changes
          ? (s.check == 'at_run' ? S.current.checkAtRun : S.current.checkNow)
          : null,
      checked: s.check != 'at_run',
      argsNote: s.secret.isEmpty ? null : S.current.planSecretNote,
      warn: s.warn,
      why: s.reason,
      ticked: choice?.ticked,
      tickReason:
          choice?.locked ??
          (choice?.needs == null || choice?.ticked == null
              ? null
              : S.current.stepSkippedNeeds(choice!.needs!)),
      note: switch (choice) {
        StepChoice(:final needs?) => S.current.stepSkippedNeeds(needs),
        StepChoice(ticked: false) => S.current.stepLeftOut,
        // no tick, and it runs: the person cannot leave it out
        StepChoice(byAgent: true) => S.current.stepByAgent,
        _ when s.after.isNotEmpty =>
          s.after.map((n) => S.current.planNeedsStep(n)).join(' · '),
        _ => null,
      },
      result: s.result == null
          ? null
          : '${s.result!.status} · ${s.result!.message}',
      resultTone: switch (s.result?.status) {
        'ok' => .good,
        'failed' => .bad,
        _ => .neutral,
      },
    );
  }

  static String _num(double v) =>
      v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

  /// A value of a step as it is sent, whole: text as it is, anything else
  /// as JSON.
  static String _shown(Object? v) => switch (v) {
    final String s => s,
    _ => jsonEncode(v, toEncodable: _bytes),
  };

  /// Binary in a value: its length (JSON has no bytes).
  static Object? _bytes(Object? v) =>
      v is Uint8List ? '<${v.length} bytes>' : '$v';

  List<TaskSectionVm> _sections(String? selected) {
    final now = <TaskItemVm>[];
    final earlier = <TaskItemVm>[];
    for (final id in tasks.view.reversed) {
      final t = tasks.table[id];
      if (t == null) {
        continue;
      }
      final item = TaskItemVm(
        id: t.id,
        title: _title(t),
        state: _stateLabel(t.state),
        tone: _tone(t.state),
        detail: _detail(t),
        selected: t.id == selected,
      );
      (t.state == .done || t.state == .failed ? earlier : now).add(item);
    }
    return [
      if (now.isNotEmpty)
        TaskSectionVm(label: S.current.sectionNow, tasks: now),
      if (earlier.isNotEmpty)
        TaskSectionVm(label: S.current.sectionEarlier, tasks: earlier),
    ];
  }

  static String _cfgLabel(String k) => switch (k) {
    'model' => S.current.cfgModel,
    'require_approval' => S.current.cfgApproval,
    'allowed_prefixes' => S.current.cfgPrefixes,
    'budget_tokens_day' => S.current.cfgBudget,
    'api_key_ref' => S.current.cfgApiKey,
    _ => humanize(k),
  };

  static String _title(AgentTask t) => t.ask.isEmpty ? t.id : t.ask;

  static List<ConversationEventVm> _conversation(List<TaskEvent> events) {
    final out = <ConversationEventVm>[];
    var reads = <String>[];
    void flush() {
      if (reads.isNotEmpty) {
        out.add(ConversationEventVm(kind: .reads, reads: reads));
        reads = [];
      }
    }

    for (final e in events) {
      if (e.kind == 'tool') {
        reads.add('read · ${e.text}');
        continue;
      }
      flush();
      out.add(switch (e.kind) {
        'ask' => ConversationEventVm(kind: .ask, text: e.text),
        'state' => ConversationEventVm(
          kind: .state,
          text: _stateLabel(_stateOf(e.text)),
          tone: _tone(_stateOf(e.text)),
        ),
        'error' => ConversationEventVm(kind: .error, text: e.text),
        'note' => ConversationEventVm(kind: .state, text: e.text),
        _ => ConversationEventVm(kind: .text, text: e.text),
      });
    }
    flush();
    return out;
  }

  TaskCardVm _card(AgentTask t, String? reason, List<StepChoice>? choices) {
    final agent = assistant.agent;
    final ticked = choices?.where((c) => c.ticked ?? false).length ?? 0;
    // every change that runs once approved: the ticked steps, and those the
    // agent runs with its own key (no tick, cannot be left out)
    final runs = choices?.where((c) => c.runs).length ?? 0;
    final byAgent = choices?.where((c) => c.byAgent && !c.skipped).length ?? 0;
    final refusal = assistant.refusals[t.id];
    final left = _leftOut(t);
    final cancel = TaskButtonVm(
      id: 'cancel',
      label: S.current.cancelTask,
      danger: true,
      disabledReason: reason,
    );
    return switch (t.state) {
      .awaitingApproval => TaskCardVm(
        title: S.current.planCard,
        note: switch (null) {
          // a gateway older than `doc` cannot show the plan: the old note
          _ when !assistant.docs => S.current.planNote,
          _ when otherSite != null => S.current.approveOtherSite(otherSite!),
          // the task keeps waiting: what was refused, and the way on
          _ when refusal != null =>
            '${S.current.approveRefused(refusal)}\n'
                '${S.current.approveRefusedHint}',
          _ when !t.recorded => S.current.planWaiting,
          _ => [
            S.current.approveSigns(site.role ?? ''),
            if (byAgent > 0) S.current.approveByAgent(byAgent),
          ].join('\n'),
        },
        caution: !assistant.docs || otherSite != null || refusal != null,
        buttons: [
          TaskButtonVm(
            id: 'reject',
            label: S.current.reject,
            disabledReason: reason,
          ),
          TaskButtonVm(
            id: 'approve',
            label: ticked == 0
                ? S.current.approve
                : S.current.approveCount(runs),
            primary: true,
            disabledReason: switch (null) {
              _ when !assistant.docs => S.current.approveReasonNote,
              _ when otherSite != null => S.current.approveOtherSite(
                otherSite!,
              ),
              _ when _approving => '…',
              _ when ticked == 0 => S.current.approveNone,
              _ =>
                agent == null
                    ? null
                    : site.needs('write', '$agent/tasks/${t.id}'),
            },
          ),
        ],
      ),
      .planning || .running => TaskCardVm(
        title: _stateLabel(t.state),
        note: S.current.runningNote,
        buttons: [cancel],
      ),
      .done => TaskCardVm(
        title: _stateLabel(t.state),
        note: left.isEmpty
            ? S.current.doneNote
            : S.current.doneLeftOutNote(left.join(', ')),
        buttons: [
          if (left.isNotEmpty)
            TaskButtonVm(
              id: 'followup',
              label: S.current.followUpLeftOut,
              primary: true,
              disabledReason:
                  (agent == null ? null : site.needs('write', agent)) ??
                  (_asking ? '…' : null),
            ),
        ],
      ),
      .failed => TaskCardVm(
        title: _stateLabel(t.state),
        note: t.error ?? S.current.failedNote,
        caution: true,
      ),
    };
  }

  /// Who asked and how it ended, under a task's name.
  String? _detail(AgentTask t) {
    if (!t.recorded) {
      return null;
    }
    final failedAt = t.plan
        .where((s) => s.result?.status == 'failed')
        .map((s) => s.n)
        .firstOrNull;
    final parts = [
      if (t.owner.isNotEmpty && !askedByUser(t))
        S.current.taskBy(t.owner.replaceFirst('user:', '')),
      if (failedAt != null)
        S.current.taskFailedAt(failedAt)
      else if (t.state == .done && t.plan.isEmpty)
        S.current.taskNoChanges,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static TaskState _stateOf(String s) => switch (s) {
    'awaiting_approval' => .awaitingApproval,
    'running' => .running,
    'done' => .done,
    'failed' || 'rejected' || 'cancelled' => .failed,
    _ => .planning,
  };

  static String _stateLabel(TaskState s) => switch (s) {
    .planning => S.current.taskPlanning,
    .awaitingApproval => S.current.taskAwaiting,
    .running => S.current.taskRunning,
    .done => S.current.taskDone,
    .failed => S.current.taskFailed,
  };

  static Tone _tone(TaskState s) => switch (s) {
    .planning || .running => Tone.ember,
    .awaitingApproval => Tone.warn,
    .done => Tone.good,
    .failed => Tone.bad,
  };
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.agentName,
    required this.sections,
    required this.title,
    required this.status,
    required this.taskKey,
    required this.events,
    required this.plan,
    required this.onTick,
    required this.card,
    required this.draft,
    required this.askReason,
    required this.panel,
    required this.facts,
    required this.reads,
    required this.panelNote,
    required this.empty,
    required this.onShow,
    required this.onHide,
    required this.onNew,
    required this.onTask,
    required this.onDraft,
    required this.onAsk,
    required this.onPanel,
    required this.onAddAgent,
    required this.onButton,
  }) : super(
         equals: [
           agentName,
           sections,
           title,
           status,
           taskKey,
           events,
           plan,
           card,
           draft,
           askReason,
           panel,
           facts,
           reads,
           panelNote,
           empty,
         ],
       );

  final String agentName;
  final List<TaskSectionVm> sections;
  final String? title;
  final StatusPillVm? status;
  final String? taskKey;
  final List<ConversationEventVm> events;
  final PlanCardVm? plan;
  final void Function(int n, {required bool ticked})? onTick;
  final TaskCardVm? card;
  final String draft;
  final String? askReason;
  final String panel;
  final List<FactVm> facts;
  final List<(String, String)> reads;
  final String panelNote;
  final String? empty;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final ValueChanged<String> onPanel;
  final VoidCallback onAddAgent;
  final Future<void> Function(BuildContext context, String button) onButton;
}
