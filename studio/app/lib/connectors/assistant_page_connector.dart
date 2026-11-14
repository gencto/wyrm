import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/load_assistant_action.dart';
import 'package:business/redux/assistant/actions/pick_suggestion_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_option_pick_action.dart';
import 'package:business/redux/assistant/actions/set_panel_action.dart';
import 'package:business/redux/assistant/actions/set_row_pick_action.dart';
import 'package:business/redux/assistant/actions/set_shown_action.dart';
import 'package:business/redux/assistant/actions/set_step_reveal_action.dart';
import 'package:business/redux/assistant/actions/set_step_tick_action.dart';
import 'package:business/redux/assistant/actions/set_watched_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/tasks/actions/answer_task_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:business/redux/tasks/actions/save_plan_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/labels.dart';
import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/task_event.dart';
import 'package:models/task_question.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/model_words.dart';
import 'package:ui/assistant/more_rows_card.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/reason_dialog.dart';
import 'package:ui/pages/assistant_page.dart';

import '../common/files.dart';
import '../common/tab_visibility.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// What a secret argument of a plan step is shown as.
const secretMask = '••••••';

@RoutePage()
class AssistantPageConnector extends StatelessWidget {
  const AssistantPageConnector({super.key});

  static bool _sameKeys(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onWillChange: (context, store, before, now) {
      if (store.state.assistant.shown && !_sameKeys(before.watch, now.watch)) {
        store.dispatchSync(SetWatchedAction(now.watch.lock));
      }
    },
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
        onFix: vm.onPickSuggestion,
        onReveal: vm.onReveal,
        run: vm.run,
        result: vm.result,
        more: vm.more,
        onRow: vm.onRow,
        onMore: vm.onPickSuggestion,
        stopped: vm.stopped,
        onWay: vm.onPickSuggestion,
        choices: vm.choices,
        onPick: vm.onPick,
        onAnswer: vm.onAnswer,
        card: vm.card,
        onButton: (b) => vm.onButton(context, b),
        draft: vm.draft,
        askHint: vm.askHint,
        askLabel: vm.answering ? S.current.answerButton : S.current.askButton,
        askReason: vm.askReason,
        chips: vm.chips,
        onChipRemove: vm.onChipRemove,
        addChipLabel: vm.answering ? null : S.current.addFromExplorer,
        addChipReason: vm.addChipReason,
        onAddChip: vm.onAddChip,
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
    // the ticks of a plan that waits; none where this gateway cannot sign,
    // nor for a plan another task replaced (its approve is refused)
    final choices =
        task != null &&
            task.state == .awaitingApproval &&
            task.replacedBy == null &&
            otherSite == null
        ? choicesOf(task)
        : null;
    // the Explorer selection, offered as an `@` chip of this site
    final selected = nodes.selectedNode;
    final offered =
        selected != null &&
            site.root != null &&
            selected.startsWith('${site.root}/') &&
            !assistant.chips.contains(selected)
        ? selected
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
          : _conversation(events.isEmpty ? conversationOf(task) : events),
      plan: task == null || task.plan.isEmpty ? null : _plan(task, choices),
      onTick: id == null || choices == null
          ? null
          : (n, {required ticked}) =>
                dispatchSync(SetStepTickAction(id, n, ticked: ticked)),
      choices: task == null || task.questions.isEmpty
          ? null
          : _choices(task, cancelReason),
      answering: task?.state == .awaitingAnswer,
      onPick: (question, option) {
        final q = task?.questions.where((q) => q.id == question).firstOrNull;
        if (id != null && q != null) {
          dispatchSync(
            SetOptionPickAction(id, question, option, multiple: q.multiple),
          );
        }
      },
      onAnswer: () {
        if (id != null) {
          unawaited(dispatchAndWait(AnswerTaskAction(id)));
        }
      },
      run: task == null ? null : _run(task),
      result: task == null ? null : _result(task),
      more: task == null ? const [] : _more(task),
      stopped: task == null ? null : _stopped(task),
      onPickSuggestion: (sid) {
        if (id != null) {
          unawaited(dispatchAndWait(PickSuggestionAction(id, sid)));
        }
      },
      onRow: (sid, key, {required on}) {
        if (id != null) {
          dispatchSync(SetRowPickAction(id, sid, key, on: on));
        }
      },
      onReveal: (n) {
        if (id != null) {
          dispatchSync(
            SetStepRevealAction(
              id,
              n,
              shown: !(assistant.revealed[id]?.contains(n) ?? false),
            ),
          );
        }
      },
      watch: task == null ? const [] : _touched(task),
      card: task == null ? null : _card(task, cancelReason, choices),
      draft: assistant.draft ?? '',
      askHint: _hint(task),
      chips: [for (final k in assistant.chips) (k, _short(k))],
      onChipRemove: (k) => dispatchSync(SetChipAction(k, on: false)),
      addChipReason: offered == null ? S.current.addFromExplorerNone : null,
      onAddChip: () {
        if (offered != null) {
          dispatchSync(SetChipAction(offered));
        }
      },
      askReason: agent == null
          ? S.current.noAgent
          : (site.needs('write', agent) ??
                (_asking || tasks.isAnswering ? '…' : null)),
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
        // the keys the Result card shows, watched while the tab is shown
        dispatchSync(
          SetWatchedAction(
            (task == null ? const <String>[] : _touched(task)).lock,
          ),
        );
        unawaited(dispatchAndWait(LoadAssistantAction()));
      },
      onHide: () {
        dispatchSync(SetShownAction(false));
        dispatchSync(SetWatchedAction(const IListConst([])));
      },
      onNew: () {
        dispatchSync(SetSelectedTaskAction(null));
        dispatchSync(SetPanelAction('task'));
      },
      onTask: (t) {
        dispatchSync(SetSelectedTaskAction(t));
        unawaited(dispatchAndWait(RetrieveTaskRecordAction(t)));
      },
      onDraft: (t) => dispatchSync(SetDraftAction(t)),
      // while the assistant waits for an answer, the box answers it in
      // the person's own words; else it follows the selected task (a plan
      // that waits is replaced by the new one, spec assistant.md §4)
      onAsk: () => unawaited(
        dispatchAndWait(
          id != null && task?.state == .awaitingAnswer
              ? AnswerTaskAction(id, text: assistant.draft)
              : AskAgentAction(
                  parent:
                      task != null && task.replacedBy == null && mayFollow(task)
                      ? id
                      : null,
                ),
        ),
      ),
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
          case 'replacement':
            if (task?.replacedBy case final next?) {
              dispatchSync(SetSelectedTaskAction(next));
              await dispatchAndWait(RetrieveTaskRecordAction(next));
            }
          case 'explorer':
            if (_node(task) case final node?) {
              dispatchSync(SelectNodeAction(node));
              dispatchSync(GoAction.navigate(const ExplorerRoute()));
            }
          case 'save':
            if (task != null) {
              await _save(task);
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

  /// The task's plan as it is approved: every step with its full key and
  /// every argument (docs/agent.md: never only the model's reason).
  PlanCardVm _plan(AgentTask t, List<StepChoice>? choices) => PlanCardVm(
    title: S.current.planSteps(t.plan.length),
    state: t.replacedBy != null
        ? S.current.taskReplaced('tasks/${t.replacedBy}')
        : t.state == .awaitingApproval
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
    // a plan that waits is read whole; after that its run tells the story
    open: t.state == .awaitingApproval && t.replacedBy == null,
    showLabel: S.current.showSteps,
    hideLabel: S.current.hideSteps,
    steps: [
      for (final (i, s) in t.plan.indexed) _step(t, s, choices?.elementAt(i)),
    ],
  );

  /// What the assistant asked: an answered question as one line, an open
  /// one with its options and the picks made so far.
  ChoicesCardVm _choices(AgentTask t, String? reason) {
    final open = t.state == .awaitingAnswer;
    final picked = [
      for (final q in t.questions)
        if (!q.answered) assistant.picks['${t.id}/${q.id}']?.length ?? 0,
    ];
    return ChoicesCardVm(
      title: S.current.choicesTitle,
      questions: [
        for (final q in t.questions)
          ChoiceQuestionVm(
            id: q.id,
            text: q.text,
            multiple: q.multiple,
            answer: q.answered || !open ? _answerOf(q) : null,
            options: [
              for (final o in q.options)
                ChoiceOptionVm(
                  id: o.id,
                  label: o.label,
                  detail: o.detail,
                  picked:
                      assistant.picks['${t.id}/${q.id}']?.contains(o.id) ??
                      false,
                ),
            ],
          ),
      ],
      confirm: open && picked.isNotEmpty ? S.current.choicesConfirm : null,
      confirmReason:
          reason ??
          (tasks.isAnswering
              ? '…'
              : (picked.every((n) => n == 0)
                    ? S.current.choicesPickOne
                    : null)),
      note: S.current.choicesNote,
    );
  }

  /// `from the card: Slave ID 4`, `in your own words: …`, `no answer`.
  static String _answerOf(TaskQuestion q) {
    if (q.words case final w? when w.isNotEmpty) {
      return S.current.choicesOwnWords(w);
    }
    final labels = [
      for (final o in q.options)
        if (q.picked.contains(o.id)) o.label,
    ];
    return labels.isEmpty
        ? S.current.choicesNoAnswer
        : S.current.choicesFromCard(labels.join(', '));
  }

  /// The run of a plan: one row per step with what the record says of it.
  /// None before a run (a plan that waits, a rejected one).
  RunCardVm? _run(AgentTask t) {
    final ran = t.plan.any((s) => s.result != null);
    if (t.plan.isEmpty || (t.state != .running && !ran)) {
      return null;
    }
    // what the run changed and keeps: the steps that change something and
    // ended `ok` (a cancel marks no step failed; a skipped step did nothing)
    final kept = [
      for (final s in t.plan)
        if ((s.op == 'set' || s.op == 'invoke') && s.result?.status == 'ok')
          s.n,
    ];
    final left = _leftOut(t);
    final times = [for (final s in t.plan) ?s.result?.time];
    final seconds = times.length < 2
        ? 0
        : times.last.difference(times.first).inSeconds;
    return RunCardVm(
      title: t.state == .running && t.step > 0
          ? S.current.runTitle(t.step, t.plan.length)
          : S.current.runTitleEnded(t.plan.length),
      rows: [
        for (final s in t.plan)
          RunRowVm(
            n: s.n,
            step: [
              s.op.toUpperCase(),
              ?s.action,
              if (s.op == 'sleep')
                S.current.planSleep(_num(s.seconds ?? 0))
              else
                s.key.split('/').skip(3).join('/'),
            ].join(' '),
            status: switch (s.result?.status) {
              'ok' => .ok,
              'failed' => .failed,
              'skipped' => .skipped,
              _ when t.state == .running && s.n == t.step => .running,
              _ => .waiting,
            },
            text: switch (s.result) {
              final r? => r.message.isEmpty ? r.status : r.message,
              _ when t.state == .running && s.n == t.step =>
                S.current.runRunning,
              _ when t.state == .running => S.current.runWaiting,
              _ => S.current.runNotRun,
            },
          ),
      ],
      note: switch (t.state) {
        .running => S.current.runStopsNote,
        .done when left.isNotEmpty => S.current.runPassedLeftOut(
          left.join(', '),
        ),
        .done when seconds > 0 => S.current.runPassedIn(seconds),
        .done => S.current.runPassed,
        _ when kept.isEmpty => S.current.runStoppedFirst,
        _ when kept.length == 1 => S.current.runStoppedOne(kept.single),
        _ => S.current.runStopped(kept.join(', ')),
      },
      noteTone: switch (t.state) {
        .done => .good,
        .failed => .bad,
        _ => .neutral,
      },
    );
  }

  /// The keys with a value that a finished plan touched: what it set and
  /// what it proved, at most 12, in the plan's order.
  static List<String> _touched(AgentTask t) => t.state != .done
      ? const []
      : {
          for (final s in t.plan)
            if (s.result?.status == 'ok' &&
                (s.op == 'set' || s.op == 'expect' || s.op == 'wait'))
              s.key,
        }.take(12).toList();

  /// What a finished plan left behind: the keys of [_touched] with their
  /// values now.
  ResultCardVm? _result(AgentTask t) {
    final keys = _touched(t);
    if (keys.isEmpty) {
      return null;
    }
    return ResultCardVm(
      title: S.current.resultTitle,
      facts: [
        for (final k in keys)
          (
            k.split('/').skip(3).join('/'),
            switch (live.values[k]) {
              final v? => valueText(v.value),
              null => S.current.resultNoValue,
            },
          ),
      ],
      note: S.current.resultNote,
    );
  }

  /// The node a finished plan was about: the target of its last step that
  /// changed something.
  static String? _node(AgentTask? t) => t?.plan
      .where(
        (s) => s.result?.status == 'ok' && (s.op == 'set' || s.op == 'invoke'),
      )
      .map((s) => s.key)
      .lastOrNull;

  /// Save as a plan: the folder is the user's pick (a dialog of the
  /// screen), the file is written by [SavePlanAction]. The notice says
  /// where it went and which secret arguments were left out of it.
  Future<void> _save(AgentTask t) async {
    final file = await saveInto(
      'task-${t.id}.plan.json',
      fallback: 'plan.json',
      dialogTitle: S.current.savePlanTitle(t.id),
    );
    if (file == null) {
      return;
    }
    final status = await dispatchAndWait(
      SavePlanAction(
        t.id,
        write: file.write,
        onDone: file.commit,
        onDiscard: file.discard,
      ),
    );
    if (status.isCompletedOk) {
      final left = secretsLeftOut(t);
      dispatchSync(
        ShowNoticeAction(
          S.current.planSaved(file.path),
          detail: left.isEmpty
              ? null
              : S.current.planSavedSecrets(left.join('; ')),
        ),
      );
    }
  }

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

  PlanStepVm _step(AgentTask t, PlanStep s, StepChoice? choice) {
    final changes = s.op == 'set' || s.op == 'invoke';
    final hidden = withheld(s);
    // masked because the schema is not known: the person may look
    final guessed = !s.argsKnown && hidden.isNotEmpty;
    final shown = guessed && (assistant.revealed[t.id]?.contains(s.n) ?? false);
    // the fixes the model offers for this step, while the plan waits
    final fixes = t.state == .awaitingApproval && t.replacedBy == null
        ? [
            for (final f in t.suggestions)
              if (f.step == s.n)
                _tile(
                  t,
                  f,
                  note: switch (_unattended) {
                    final mode? => S.current.fixReplacesNoPerson(mode),
                    null => S.current.fixReplaces,
                  },
                ),
          ]
        : const <SuggestionTileVm>[];
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
            s.secret.contains(e.key) || (hidden.contains(e.key) && !shown)
                ? secretMask
                : _shown(e.value),
          ),
        if (s.op != 'sleep')
          if (s.seconds case final sec?)
            ('timeout', S.current.planSleep(_num(sec))),
      ],
      check: changes
          ? (s.check == 'at_run' ? S.current.checkAtRun : S.current.checkNow)
          : null,
      checked: s.check != 'at_run',
      argsNote: guessed
          ? S.current.argsMasked
          : (s.secret.isEmpty ? null : S.current.planSecretNote),
      revealLabel: guessed
          ? (shown ? S.current.hideArgs : S.current.showArgs)
          : null,
      warn: s.warn,
      modelWarn: switch (s.modelWarn) {
        final w? when w.isNotEmpty => ModelWordsVm(
          label: S.current.modelSays,
          text: w,
        ),
        _ => null,
      },
      fixes: fixes,
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
      // the question itself is on the choices card
      if (e.kind == 'question') {
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
        'answer' => ConversationEventVm(
          kind: .ask,
          text: S.current.choicesFromCard(e.text),
        ),
        'note' => ConversationEventVm(kind: .state, text: e.text),
        _ => ConversationEventVm(kind: .text, text: e.text),
      });
    }
    flush();
    return out;
  }

  TaskCardVm? _card(AgentTask t, String? reason, List<StepChoice>? choices) {
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
    // a plan another task took the place of: never approved, and the way
    // to the task that replaced it (its `~val` may still say it waits)
    if (t.replacedBy case final next?) {
      return TaskCardVm(
        title: S.current.replacedTitle,
        note: S.current.replacedNote(next),
        buttons: [
          TaskButtonVm(
            id: 'replacement',
            label: S.current.openReplacement(next),
            primary: true,
          ),
        ],
      );
    }
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
      .awaitingAnswer => TaskCardVm(
        title: _stateLabel(t.state),
        note: S.current.answerWaitingNote,
        buttons: [cancel],
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
          if (_node(t) case final node?)
            TaskButtonVm(
              id: 'explorer',
              label: S.current.openNodeInExplorer(node.split('/').last),
            ),
          if (t.plan.isNotEmpty)
            TaskButtonVm(id: 'save', label: S.current.saveAsPlan),
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
      .failed => switch (t.plan
          .where((s) => s.result?.status == 'failed')
          .firstOrNull) {
        // stopped in its run: the Stopped card says where and what next;
        // while the model reviews the run it can be cancelled
        _? when t.reviewing => TaskCardVm(
          title: _stateLabel(t.state),
          note: S.current.runningNote,
          buttons: [cancel],
        ),
        _? => null,
        null => TaskCardVm(
          title: _stateLabel(t.state),
          note: t.error ?? S.current.failedNote,
          caution: true,
        ),
      },
    };
  }

  /// Why a suggestion of [t] cannot be picked: no agent, no write on it,
  /// an ask in flight, or the user may not follow the task up.
  String? _followReason(AgentTask t) {
    final agent = assistant.agent;
    if (agent == null) {
      return S.current.noAgent;
    }
    return site.needs('write', agent) ??
        (_asking ? '…' : null) ??
        (mayFollow(t) ? null : S.current.followNeeds);
  }

  /// A suggestion as a tile: the model's words as plain text, its guessed
  /// changes as the tag.
  SuggestionTileVm _tile(AgentTask t, TaskSuggestion s, {String? note}) =>
      SuggestionTileVm(
        id: s.id,
        label: s.label,
        detail: s.detail,
        tag: S.current.changesGuess(s.changes),
        tagTone: s.changes == 0 ? .neutral : .ember,
        note: note,
        disabledReason: _followReason(t),
      );

  /// *Same for more units?* of a task that is done: the suggestions with
  /// rows, each row tickable, none ticked at first.
  List<MoreRowsCardVm> _more(AgentTask t) {
    if (t.state != .done) {
      return const [];
    }
    return [
      for (final s in t.suggestions)
        if (s.rows.isNotEmpty)
          () {
            final picked =
                assistant.rowPicks['${t.id}/${s.id}'] ??
                const ISetConst<String>({});
            final n = s.rows.where((r) => picked.contains(r.key)).length;
            return MoreRowsCardVm(
              id: s.id,
              title: s.label,
              detail: s.detail,
              rows: [
                for (final r in s.rows)
                  MoreRowVm(
                    key: r.key,
                    label: r.label,
                    detail: r.detail,
                    ticked: picked.contains(r.key),
                  ),
              ],
              button: S.current.moreButton(n),
              disabledReason:
                  _followReason(t) ?? (n == 0 ? S.current.moreNone : null),
              note: switch (_unattended) {
                final mode? => S.current.waysCaution(mode),
                null => S.current.moreNote,
              },
            );
          }(),
    ];
  }

  /// Where a run stopped, what the model read about it, and its ways out
  /// (every suggestion the review left: a failed task keeps only those).
  StoppedCardVm? _stopped(AgentTask t) {
    if (t.state != .failed || t.replacedBy != null) {
      return null;
    }
    final at = t.plan.where((s) => s.result?.status == 'failed').firstOrNull;
    if (at == null) {
      return null;
    }
    final message = at.result!.message.isEmpty
        ? (t.error ?? S.current.failedNote)
        : at.result!.message;
    final code = RegExp('^([a-z][a-z0-9_]*):').firstMatch(message)?[1];
    return StoppedCardVm(
      title: code == null
          ? S.current.stoppedAt(at.n)
          : S.current.stoppedAtCode(at.n, code),
      message: S.current.stoppedNote(message),
      reviewing: t.reviewing ? S.current.reviewingNote : null,
      review: switch (t.review) {
        final r? when !t.reviewing => ModelWordsVm(
          label: S.current.modelReviewed,
          text: r,
        ),
        _ => null,
      },
      waysLabel: S.current.waysOut,
      ways: [for (final s in t.suggestions) _tile(t, s)],
      // docs/agent.md: with these modes a pick may write without a person
      caution: switch (_unattended) {
        final mode? => S.current.waysCaution(mode),
        null => null,
      },
      note: t.suggestions.isEmpty ? null : S.current.waysNote,
    );
  }

  /// The agent's `require_approval` when it lets a plan's `write` steps
  /// run without a person (`config`, `never`): a picked suggestion's plan
  /// may then write at once (docs/agent.md, AI-4). Null for `write`.
  String? get _unattended => switch (assistant.cfg['require_approval']) {
    final m? when m == 'config' || m == 'never' => m,
    _ => null,
  };

  /// The composer's hint for the task on screen (spec `assistant.md` §4).
  String _hint(AgentTask? t) => switch (t?.state) {
    null => S.current.askHint,
    .awaitingAnswer => S.current.answerHint,
    .planning => S.current.hintPlanning,
    .awaitingApproval when t!.replacedBy == null => S.current.hintAwaiting,
    .running => S.current.hintRunning,
    .done => S.current.hintDone,
    .failed when t!.replacedBy == null => S.current.hintFailed(
      _short(
        t.plan
                .where((s) => s.result?.status == 'failed')
                .map((s) => s.key)
                .firstOrNull ??
            t.id,
      ).split('/').last,
    ),
    _ => S.current.hintDone,
  };

  /// A key as it is shown in a chip: below the site, without `downstream/`.
  static String _short(String key) {
    final below = key.split('/').skip(2).join('/');
    return below.startsWith('downstream/')
        ? below.substring('downstream/'.length)
        : below;
  }

  /// Who asked and how it ended, under a task's name.
  String? _detail(AgentTask t) {
    if (!t.recorded && t.replacedBy == null) {
      return null;
    }
    final failedAt = t.plan
        .where((s) => s.result?.status == 'failed')
        .map((s) => s.n)
        .firstOrNull;
    final parts = [
      if (t.owner.isNotEmpty && !askedByUser(t))
        S.current.taskBy(t.owner.replaceFirst('user:', '')),
      if (t.replacedBy case final next?)
        S.current.taskReplaced(next)
      else if (failedAt != null)
        S.current.taskFailedAt(failedAt)
      else if (t.state == .done && t.plan.isEmpty)
        S.current.taskNoChanges,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static TaskState _stateOf(String s) => switch (s) {
    'awaiting_approval' => .awaitingApproval,
    'awaiting_answer' => .awaitingAnswer,
    'running' => .running,
    'done' => .done,
    'failed' || 'rejected' || 'cancelled' => .failed,
    _ => .planning,
  };

  static String _stateLabel(TaskState s) => switch (s) {
    .planning => S.current.taskPlanning,
    .awaitingAnswer => S.current.taskAwaitingAnswer,
    .awaitingApproval => S.current.taskAwaiting,
    .running => S.current.taskRunning,
    .done => S.current.taskDone,
    .failed => S.current.taskFailed,
  };

  static Tone _tone(TaskState s) => switch (s) {
    .planning || .running => Tone.ember,
    .awaitingApproval || .awaitingAnswer => Tone.warn,
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
    required this.run,
    required this.result,
    required this.more,
    required this.stopped,
    required this.onPickSuggestion,
    required this.onRow,
    required this.onReveal,
    required this.choices,
    required this.answering,
    required this.onPick,
    required this.onAnswer,
    required this.watch,
    required this.card,
    required this.draft,
    required this.askHint,
    required this.chips,
    required this.onChipRemove,
    required this.addChipReason,
    required this.onAddChip,
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
           run,
           result,
           more,
           stopped,
           choices,
           answering,
           watch,
           card,
           draft,
           askHint,
           chips,
           addChipReason,
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
  final RunCardVm? run;
  final ResultCardVm? result;
  final List<MoreRowsCardVm> more;
  final StoppedCardVm? stopped;

  /// A suggestion (a fix, a way out, more units) of the task was picked.
  final ValueChanged<String> onPickSuggestion;
  final void Function(String suggestion, String key, {required bool on}) onRow;
  final ValueChanged<int> onReveal;
  final ChoicesCardVm? choices;

  /// The task waits for the person's answer: the box answers it.
  final bool answering;
  final void Function(String question, String option) onPick;
  final VoidCallback onAnswer;

  /// The keys whose values the Result card shows.
  final List<String> watch;
  final TaskCardVm? card;
  final String draft;
  final String askHint;
  final List<ChipVm> chips;
  final ValueChanged<String> onChipRemove;
  final String? addChipReason;
  final VoidCallback onAddChip;
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
