import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_panel_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/retrieve_tasks_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/labels.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/agent_task.dart';
import 'package:models/task_event.dart';
import 'package:models/task_state.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/pages/assistant_page.dart';

import '../common/tab_visibility.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class AssistantPageConnector extends StatelessWidget {
  const AssistantPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: () {},
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
          : _conversation(events),
      card: task == null ? null : _card(task, cancelReason),
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
      onShow: () => unawaited(_load()),
      onNew: () {
        dispatchSync(SetSelectedTaskAction(null));
        dispatchSync(SetPanelAction('task'));
      },
      onTask: (t) => dispatchSync(SetSelectedTaskAction(t)),
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
            await dispatchAndWait(ApproveTaskAction(id));
          case 'reject':
            if (await ConfirmDialog.ask(
              context,
              title: S.current.reject,
              message: S.current.failedNote,
              confirm: S.current.reject,
              cancel: S.current.cancel,
            )) {
              await dispatchAndWait(RejectTaskAction(id));
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

  bool get _loading => assistant.isWaiting || links.isWaiting;

  Future<void> _load() async {
    if (links.table.isEmpty) {
      await dispatchAndWait(RetrieveLinksAction());
    }
    await dispatchAndWait(RetrieveAgentAction());
    await dispatchAndWait(RetrieveTasksAction());
  }

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
        _ => ConversationEventVm(kind: .text, text: e.text),
      });
    }
    flush();
    return out;
  }

  TaskCardVm _card(AgentTask t, String? reason) {
    final cancel = TaskButtonVm(
      id: 'cancel',
      label: S.current.cancelTask,
      danger: true,
      disabledReason: reason,
    );
    return switch (t.state) {
      .awaitingApproval => TaskCardVm(
        title: S.current.planCard,
        note: S.current.planNote,
        buttons: [
          TaskButtonVm(
            id: 'reject',
            label: S.current.reject,
            disabledReason: reason,
          ),
          TaskButtonVm(
            id: 'approve',
            label: S.current.approve,
            primary: true,
            disabledReason: S.current.approveReasonNote,
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
        note: S.current.doneNote,
      ),
      .failed => TaskCardVm(
        title: _stateLabel(t.state),
        note: t.error ?? S.current.failedNote,
      ),
    };
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
    required this.card,
    required this.draft,
    required this.askReason,
    required this.panel,
    required this.facts,
    required this.reads,
    required this.panelNote,
    required this.empty,
    required this.onShow,
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
  final TaskCardVm? card;
  final String draft;
  final String? askReason;
  final String panel;
  final List<FactVm> facts;
  final List<(String, String)> reads;
  final String panelNote;
  final String? empty;
  final VoidCallback onShow;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final ValueChanged<String> onPanel;
  final VoidCallback onAddAgent;
  final Future<void> Function(BuildContext context, String button) onButton;
}
