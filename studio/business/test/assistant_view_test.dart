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
import 'package:business/wyrm/assistant_view.dart';
import 'package:business/wyrm/context_keys.dart';
import 'package:business/wyrm/task_facts.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/agent_task.dart';
import 'package:models/live_value.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_result.dart';
import 'package:models/step_status.dart';
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
      final before = assistantInputsOf(s.state, drawer: false);

      s
        ..dispatchSync(SetTreeFilterAction('q'))
        ..dispatchSync(
          SetLiveValuesAction({'wy/central/downstream/other/x': sample(1)}),
        );
      expect(same(assistantInputsOf(s.state, drawer: false), before), isTrue);

      s.dispatchSync(SetLiveValuesAction({sp: sample(2)}));
      expect(same(assistantInputsOf(s.state, drawer: false), before), isFalse);
    });

    test('the draft is a part of it', () {
      final before = assistantInputsOf(s.state, drawer: false);
      s.dispatchSync(SetDraftAction('add ahu3'));
      expect(same(assistantInputsOf(s.state, drawer: false), before), isFalse);
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

class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}
