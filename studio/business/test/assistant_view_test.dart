import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/pick_chip_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_shown_action.dart';
import 'package:business/redux/assistant/actions/set_watched_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/tasks/actions/add_tasks_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/assistant_view.dart';
import 'package:business/wyrm/context_keys.dart';
import 'package:business/wyrm/task_facts.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/agent_task.dart';
import 'package:models/assistant_panel.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_args_note.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_result.dart';
import 'package:models/step_status.dart';
import 'package:models/step_wait.dart';
import 'package:models/task_finding.dart';
import 'package:models/task_row.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import 'support/fake_wyrm.dart';

/// What the Assistant decides from the state and one task
/// (`AssistantView`, `TaskFacts`), the parts of the state a view of it is
/// made of ([assistantInputsOf]) and the actions that read the state when
/// they run.
void main() {
  late Store<AppState> s;
  const sp = 'wy/central/downstream/modbus/tcp/ahu2/sp';

  setUp(() async {
    final login = FakeLogin();
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  _Reader read() => _Reader(s.state);

  PlanStep step(int n, {StepStatus? status}) => PlanStep(
    kind: StepKind.set,
    key: sp,
    level: Perm.write,
    n: n,
    result: status == null ? null : StepResult(status: status),
  );

  group('the card under a task', () {
    test('another task took its place: only the way to it', () {
      const t = AgentTask(
        id: 't-1',
        state: TaskState.awaitingApproval,
        replacedBy: 't-2',
      );
      final standing = read().standingOf(t, null);
      expect(standing, isA<StandingReplaced>());
      expect((standing! as StandingReplaced).by, 't-2');
      expect(t.waitsForApproval, isFalse);
    });

    test('a plan that waits: nothing ticked approves nothing', () {
      final t = AgentTask(
        id: 't-1',
        state: TaskState.awaitingApproval,
        plan: [step(1)].lock,
      );
      expect(t.waitsForApproval, isTrue);
      final standing = read().standingOf(t, const []);
      expect(standing, isA<StandingApproval>());
      expect((standing! as StandingApproval).runs, 0);
      expect((standing as StandingApproval).approveHold, isNotNull);
    });

    test('asked, planning and running: a card that can be cancelled', () {
      expect(
        read().standingOf(
          const AgentTask(id: 't', state: TaskState.awaitingAnswer),
          null,
        ),
        isA<StandingAnswer>(),
      );
      for (final state in [TaskState.planning, TaskState.running]) {
        expect(
          read().standingOf(AgentTask(id: 't', state: state), null),
          isA<StandingWorking>(),
        );
      }
    });

    test('done: what it changed, its trend, and the steps left out', () {
      final t = AgentTask(
        id: 't-1',
        state: TaskState.done,
        plan: [
          step(1, status: StepStatus.ok),
          step(2, status: StepStatus.skipped),
        ].lock,
      );
      final standing = read().standingOf(t, null)! as StandingDone;
      expect(standing.task, 't-1');
      expect(standing.changedNode, sp);
      expect(standing.trendPoint, sp);
      expect(standing.leftOut, [2]);
      expect(standing.savable, isTrue);
    });

    test('failed before a step: why; stopped at a step: the Stopped card '
        'has it, but a reviewed run can be cancelled', () {
      const early = AgentTask(id: 't', state: TaskState.failed, error: 'no');
      expect(
        (read().standingOf(early, null)! as StandingFailed).error,
        'no',
      );
      expect(early.stoppedAt, isNull);

      final stopped = AgentTask(
        id: 't',
        state: TaskState.failed,
        plan: [step(1, status: StepStatus.failed)].lock,
      );
      expect(read().standingOf(stopped, null), isNull);
      expect(stopped.stoppedAt?.n, 1);
      expect(
        read().standingOf(stopped.copyWith(reviewing: true), null),
        isA<StandingWorking>(),
      );
      // a replaced task shows no Stopped card
      expect(stopped.copyWith(replacedBy: 't-2').stoppedAt, isNull);
    });
  });

  test("the drawer's second button: a draft while the plan waits, a "
      'follow-up after a done task, none otherwise', () {
    final offer = [const TaskSuggestion(id: 's1', label: 'Also ahu3')].lock;
    AgentTask task(TaskState state, {String? replacedBy}) => AgentTask(
      id: 't',
      state: state,
      suggestions: offer,
      replacedBy: replacedBy,
    );
    final waits = read().secondOf(task(TaskState.awaitingApproval))!;
    expect(waits.draft, isTrue);
    expect(waits.suggestion.id, 's1');
    expect(read().secondOf(task(TaskState.done))!.draft, isFalse);
    expect(read().secondOf(task(TaskState.running)), isNull);
    expect(read().secondOf(task(TaskState.done, replacedBy: 't-2')), isNull);
    expect(
      read().secondOf(const AgentTask(id: 't', state: TaskState.done)),
      isNull,
    );
  });

  test('the line under a plan: replaced, checked while it waits, approved, '
      'else its state', () {
    final waits = AgentTask(
      id: 't',
      state: TaskState.awaitingApproval,
      plan: [step(1)].lock,
    );
    expect(
      (read().planLineOf(waits) as PlanLineChecked).checks,
      const PlanChecks(now: 1, atRun: 0),
    );
    expect(
      (read().planLineOf(
        waits.copyWith(replacedBy: 't-2'),
      ) as PlanLineReplaced).by,
      't-2',
    );
    const done = AgentTask(id: 't', state: TaskState.done);
    expect(
      (read().planLineOf(
        done.copyWith(approvedBy: 'by olena'),
      ) as PlanLineApproved).by,
      'by olena',
    );
    expect(read().planLineOf(done), isA<PlanLineState>());
  });

  test('the ask box: what it invites to, for the tab and for the drawer', () {
    ComposerCue cue(TaskState state, {bool drawer = false}) => read()
        .composerOf(
          AgentTask(id: 't', state: state),
          drawer: drawer,
        )
        .cue;
    expect(read().composerOf(null, drawer: false).cue, ComposerCue.ask);
    expect(cue(TaskState.planning), ComposerCue.planning);
    expect(cue(TaskState.running), ComposerCue.running);
    expect(cue(TaskState.done), ComposerCue.done);
    expect(cue(TaskState.failed), ComposerCue.failed);
    expect(cue(TaskState.awaitingAnswer), ComposerCue.answer);
    // the drawer has its own invitation, but a question is answered there
    expect(cue(TaskState.done, drawer: true), ComposerCue.drawer);
    expect(cue(TaskState.awaitingAnswer, drawer: true), ComposerCue.answer);
    const asked = AgentTask(id: 't', state: TaskState.awaitingAnswer);
    expect(read().composerOf(asked, drawer: false).answering, isTrue);
    expect(read().answersOpen(asked), isTrue);
    // nothing asked: nothing to confirm
    expect(read().confirmsAnswer(asked), isFalse);
    final stopped = AgentTask(
      id: 't',
      state: TaskState.failed,
      plan: [step(1, status: StepStatus.failed)].lock,
    );
    expect(read().composerOf(stopped, drawer: false).node, sp);
    expect(
      read().composerOf(stopped.copyWith(replacedBy: 'x'), drawer: false).cue,
      ComposerCue.done,
    );
  });

  test('more units are offered once the task is done', () {
    final rows = [
      TaskSuggestion(
        id: 's',
        label: 'Same for',
        rows: [const TaskRow(key: 'k', label: 'ahu3')].lock,
      ),
    ].lock;
    AgentTask task(TaskState state) =>
        AgentTask(id: 't', state: state, suggestions: rows);
    expect(read().moreOf(task(TaskState.done)), hasLength(1));
    expect(read().moreOf(task(TaskState.running)), isEmpty);
  });

  group('what a view of the Assistant is made of', () {
    bool same(List<Object?> a, List<Object?> b) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!identical(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }

    LiveValue sample(int v) =>
        LiveValue(time: DateTime(2026, 11, 15, 12), value: v);

    setUp(() {
      s
        ..dispatchSync(
          AddTasksAction(
            [
              AgentTask(
                id: 't-1',
                state: TaskState.done,
                plan: [step(1, status: StepStatus.ok)].lock,
              ),
            ].lock,
          ),
        )
        ..dispatchSync(SetSelectedTaskAction('t-1'));
    });

    test('a dispatch elsewhere and a value of another key change none of '
        'it; a value of a key it shows does', () {
      final before = assistantInputsOf(
        s.state,
        const Waiting.none(),
        drawer: false,
      );

      s
        ..dispatchSync(SetTreeFilterAction('q'))
        ..dispatchSync(
          SetLiveValuesAction({'wy/central/downstream/other/x': sample(1)}),
        );
      expect(
        same(
          assistantInputsOf(s.state, const Waiting.none(), drawer: false),
          before,
        ),
        isTrue,
      );

      s.dispatchSync(SetLiveValuesAction({sp: sample(2)}));
      expect(
        same(
          assistantInputsOf(s.state, const Waiting.none(), drawer: false),
          before,
        ),
        isFalse,
      );
    });

    test('the draft is a part of it', () {
      final before = assistantInputsOf(
        s.state,
        const Waiting.none(),
        drawer: false,
      );
      s.dispatchSync(SetDraftAction('add ahu3'));
      expect(
        same(
          assistantInputsOf(s.state, const Waiting.none(), drawer: false),
          before,
        ),
        isFalse,
      );
    });
  });

  group('the keys the tab watches', () {
    setUp(() {
      s
        ..dispatchSync(
          AddTasksAction(
            [
              AgentTask(
                id: 't-1',
                state: TaskState.done,
                plan: [step(1, status: StepStatus.ok)].lock,
              ),
            ].lock,
          ),
        )
        ..dispatchSync(SetSelectedTaskAction('t-1'));
    });

    test('are read when the action runs, while the tab is shown', () {
      s
        ..dispatchSync(SetShownAction(true))
        ..dispatchSync(SetWatchedAction.shown());
      expect(s.state.assistant.watched, [sp]);
      expect(s.state.live.watched.keys, contains(sp));

      s
        ..dispatchSync(SetSelectedTaskAction(null))
        ..dispatchSync(SetWatchedAction.shown());
      expect(s.state.assistant.watched, isEmpty);
      expect(s.state.live.watched.keys, isNot(contains(sp)));
    });

    test('are left as they are while the tab is hidden', () {
      s.dispatchSync(SetWatchedAction.shown());
      expect(s.state.assistant.watched, isEmpty);
      expect(s.state.live.watched.keys, isNot(contains(sp)));
    });
  });

  group('what the cards of a task show', () {
    test('the plan, the choices, the result and the run card', () {
      const none = AgentTask(id: 't-0');
      expect(none.showsPlan, isFalse);
      expect(none.showsChoices, isFalse);
      expect(none.showsResult, isFalse);
      expect(none.showsRun, isFalse);

      final waits = AgentTask(
        id: 't-1',
        state: TaskState.awaitingApproval,
        plan: [step(1)].lock,
      );
      expect(waits.showsPlan, isTrue);
      expect(waits.showsRun, isFalse, reason: 'no run before an approval');

      final runs = AgentTask(
        id: 't-2',
        state: TaskState.running,
        step: 2,
        plan: [step(1, status: StepStatus.ok), step(2), step(3)].lock,
      );
      expect(runs.showsRun, isTrue);
      expect(runs.runEnded, isFalse);
      expect(runs.waitOf(runs.plan[1]), StepWait.running);
      expect(runs.waitOf(runs.plan[2]), StepWait.waiting);

      final done = runs.copyWith(state: TaskState.done, step: 0);
      expect(done.showsRun, isTrue);
      expect(done.runEnded, isTrue);
      expect(done.waitOf(done.plan[1]), StepWait.waiting);
      expect(done.showsResult, isTrue);
    });

    test('fixes only while the plan waits', () {
      const fix = TaskSuggestion(id: 'f', label: 'use 21', step: 1);
      final waits = AgentTask(
        id: 't-1',
        state: TaskState.awaitingApproval,
        plan: [step(1)].lock,
        suggestions: [fix].lock,
      );
      expect(waits.fixesShownOf(1), [fix]);
      expect(waits.copyWith(state: TaskState.done).fixesShownOf(1), isEmpty);
      expect(waits.copyWith(replacedBy: 't-2').fixesShownOf(1), isEmpty);
    });

    test('a task row: who asked, where it failed, that it changed nothing', () {
      final failed = AgentTask(
        id: 't-1',
        state: TaskState.failed,
        owner: 'user:olena',
        recorded: true,
        plan: [
          step(1, status: StepStatus.ok),
          step(2, status: StepStatus.failed),
        ].lock,
      );
      expect(failed.byOf(own: false), 'olena');
      expect(failed.byOf(own: true), isNull);
      expect(failed.failedAt, 2);
      expect(failed.copyWith(recorded: false).byOf(own: false), isNull);
      expect(failed.copyWith(recorded: false).failedAt, isNull);
      expect(failed.copyWith(owner: '').byOf(own: false), isNull);
      const empty = AgentTask(id: 't-2', state: TaskState.done, recorded: true);
      expect(empty.noChanges, isTrue);
      expect(empty.copyWith(recorded: false).noChanges, isFalse);
      expect(failed.noChanges, isFalse);
    });

    test('a step: its sleep, its timeout, the note under its arguments', () {
      const sleep = PlanStep(
        kind: StepKind.sleep,
        key: '',
        level: Perm.read,
        seconds: 5,
      );
      expect(sleep.sleepSeconds, 5);
      expect(sleep.timeoutArg, isNull);
      const wait = PlanStep(
        kind: StepKind.wait,
        key: sp,
        level: Perm.read,
        seconds: 10,
      );
      expect(wait.sleepSeconds, isNull);
      expect(wait.timeoutArg, 10);
      expect(
        const PlanStep(
          kind: StepKind.sleep,
          key: '',
          level: Perm.read,
        ).sleepSeconds,
        0,
      );

      final plain = step(1);
      expect(plain.argsGuessed, isFalse);
      expect(plain.argsNote, isNull);
      final secret = plain.copyWith(
        args: {'password': 'x'}.lock,
        secret: {'password'}.lock,
      );
      expect(secret.argsNote, StepArgsNote.secret);
      final unknown = plain.copyWith(
        kind: StepKind.invoke,
        action: 'add',
        args: {'host': 'h'}.lock,
        argsKnown: false,
      );
      expect(unknown.argsGuessed, isTrue);
      expect(unknown.argsNote, StepArgsNote.masked);
    });

    test('the note under a step: needs, left out, by the agent, after', () {
      final s2 = step(2).copyWith(after: [1].lock);
      expect(
        s2.noteWith(const StepChoice(n: 2, ticked: true, needs: 1)),
        const StepNoteNeeds(1),
      );
      expect(
        s2.noteWith(const StepChoice(n: 2, ticked: false)),
        const StepNoteLeftOut(),
      );
      expect(
        s2.noteWith(const StepChoice(n: 2, byAgent: true)),
        const StepNoteByAgent(),
      );
      expect(s2.noteWith(null), const StepNoteAfter([1]));
      expect(step(1).noteWith(null), isNull);
    });

    test('masked arguments are revealed only where they were guessed', () {
      final guessed = step(1).copyWith(
        kind: StepKind.invoke,
        args: {'host': 'h'}.lock,
        argsKnown: false,
      );
      final t = AgentTask(
        id: 't-1',
        state: TaskState.awaitingApproval,
        plan: [guessed].lock,
      );
      expect(read().revealedShown(t, guessed), isFalse);
      expect(read().revealedShown(t, step(1)), isNull);
    });

    test('No tasks yet, the rights panel, What I found', () {
      final base = AppState.initial().copyWith.site(name: 'central');
      expect(_Reader(base).showsNoTasks, isFalse, reason: 'no agent');
      final agent = base.copyWith.assistant(agent: 'agent');
      expect(_Reader(agent).showsNoTasks, isTrue);
      expect(_Reader(agent).rightsShown, isFalse);
      expect(
        _Reader(
          agent.copyWith.assistant(panel: AssistantPanel.rights),
        ).rightsShown,
        isTrue,
      );
      expect(_Reader(agent).foundShown(null, drawer: true), isFalse);
      const t = AgentTask(id: 't-1', state: TaskState.done);
      expect(_Reader(agent).foundShown(t, drawer: true), isFalse);
    });

    test('What I found: in the drawer with findings, never in the tab', () {
      final t = AgentTask(
        id: 't-1',
        state: TaskState.done,
        findings: [const TaskFinding(key: sp, label: 'set point')].lock,
      );
      expect(read().foundShown(t, drawer: true), isTrue);
      expect(read().foundShown(t, drawer: false), isFalse);
    });
  });

  group('the chip picker', () {
    test('offers nothing without a site or with the chips full', () {
      expect(_Reader(AppState.initial()).chipChoices, isNull);
      expect(read().chipChoices, isNotNull);
      for (var i = 0; i < maxContextKeys; i++) {
        s.dispatchSync(PickChipAction('$sp/p$i'));
      }
      expect(read().chipChoices, isNull);
    });

    test("a chip's name: its own display name, else its name", () {
      NodeInfo info(String? display) =>
          NodeInfo(key: sp, name: 'sp', display: display);
      AppState withNode(NodeInfo n) =>
          s.state.copyWith.nodes(table: {sp: n}.lock);
      expect(_Reader(withNode(info('Set point'))).chipNameOf(sp), 'Set point');
      expect(_Reader(withNode(info('sp'))).chipNameOf(sp), 'sp');
      expect(_Reader(withNode(info('  '))).chipNameOf(sp), 'sp');
      expect(_Reader(withNode(info(null))).chipNameOf(sp), 'sp');
      expect(read().chipNameOf('wy/central/downstream/unlisted'), isNull);
    });
  });

  group('a key picked in the picker', () {
    const node = 'wy/central/downstream/modbus/tcp/ahu2';

    test('becomes a chip once, typed in full or below the site', () {
      s.dispatchSync(PickChipAction(node));
      expect(s.state.assistant.chips, [node]);

      // a chip already: nothing
      final before = s.state;
      s.dispatchSync(PickChipAction(node));
      expect(identical(s.state, before), isTrue);

      s.dispatchSync(PickChipAction('downstream/modbus/tcp/ahu3'));
      expect(s.state.assistant.chips, [
        node,
        'wy/central/downstream/modbus/tcp/ahu3',
      ]);
    });

    test('is not taken when it names no node of this site', () {
      final before = s.state;
      s
        ..dispatchSync(PickChipAction('wy/other/downstream/modbus/x'))
        ..dispatchSync(PickChipAction('wy/central/downstream/modbus/**'))
        ..dispatchSync(PickChipAction('ahu2'));
      expect(identical(s.state, before), isTrue);
    });

    test('is not taken when the chips are full', () {
      for (var i = 0; i < maxContextKeys; i++) {
        s.dispatchSync(PickChipAction('$node/p$i'));
      }
      expect(s.state.assistant.chips.length, maxContextKeys);
      final before = s.state;
      s.dispatchSync(PickChipAction('$node/one-more'));
      expect(identical(s.state, before), isTrue);
    });
  });
}

class _Reader with Selectors, NothingInFlight {
  _Reader(this.state);

  @override
  final AppState state;
}
