import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_step_tick_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:business/redux/tasks/actions/add_tasks_action.dart';
import 'package:business/redux/tasks/actions/answer_task_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:business/redux/tasks/actions/retrieve_tasks_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;
  const agent = 'wy/central/downstream/agent';

  setUp(() async {
    login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  Future<void> withAgent() async {
    api
      ..children_['wy/central/sys/links'] = [Child('agent', NodeMeta())]
      ..metas['wy/central/sys/links/agent'] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas[agent] = NodeMeta(
        cfg: {
          'model': const VStr('claude-opus-5-5'),
          'allowed_prefixes': Value.from(['wy/central/downstream/modbus']),
          'api_key_ref': const VStr('anthropic_api_key'),
        },
      );
    await s.dispatchAndWait(RetrieveLinksAction());
    await s.dispatchAndWait(RetrieveAgentAction());
  }

  test('the agent is the link of driver agent; its cfg is shown', () async {
    await withAgent();

    expect(s.state.assistant.agent, agent);
    expect(s.state.assistant.cfg['model'], 'claude-opus-5-5');
    expect(
      s.state.assistant.cfg['allowed_prefixes'],
      'wy/central/downstream/modbus',
    );
    expect(s.state.assistant.cfg['api_key_ref'], 'anthropic_api_key');
  });

  test('no agent link: no agent, asking refuses', () async {
    api.children_['wy/central/sys/links'] = [];
    await s.dispatchAndWait(RetrieveLinksAction());
    await s.dispatchAndWait(RetrieveAgentAction());
    expect(s.state.assistant.agent, isNull);

    s.dispatchSync(SetDraftAction('add ahu2'));
    final status = await s.dispatchAndWait(AskAgentAction());
    expect(status.originalError, isA<UserException>());
  });

  test('an ask streams into the task and its conversation', () async {
    await withAgent();
    api.invokes['$agent ▸ ask'] = [
      Value.from({'task': 't-1', 'state': 'planning'}),
      Value.from({'task': 't-1', 'event': 'text', 'text': 'I look at line 2.'}),
      Value.from({'task': 't-1', 'event': 'tool', 'text': 'tree'}),
      Value.from({'task': 't-1', 'event': 'wait', 'text': ''}),
      Value.from({
        'task': 't-1',
        'event': 'state',
        'text': 'awaiting_approval',
      }),
    ];
    s.dispatchSync(SetDraftAction('add ahu2'));

    await s.dispatchAndWait(AskAgentAction());

    final call = api.calls.lastWhere((c) => c.op == 'invoke');
    expect(call.args?['task'], const VStr('add ahu2'));
    final t = s.state.tasks.table['t-1']!;
    expect(t.ask, 'add ahu2');
    expect(t.state, TaskState.awaitingApproval);
    expect(s.state.tasks.selectedTask, 't-1');
    expect(s.state.assistant.draft, isNull);
    expect(
      [for (final e in s.state.tasks.events['t-1']!) '${e.kind}:${e.text}'],
      [
        'ask:add ahu2',
        'text:I look at line 2.',
        'tool:tree',
        'state:awaiting_approval',
      ],
    );
  });

  test('an ask that starts no task is an error; the ask stays', () async {
    await withAgent();
    api.invokes['$agent ▸ ask'] = [];
    s.dispatchSync(SetDraftAction('add ahu2'));

    final status = await s.dispatchAndWait(AskAgentAction());

    expect(status.originalError, isA<UserException>());
    expect(s.state.assistant.draft, 'add ahu2');
    expect(s.state.tasks.table, isEmpty);
  });

  test('tasks are listed; reject and cancel act on the task node', () async {
    await withAgent();
    api
      ..children_['$agent/tasks'] = [Child('t-1', NodeMeta())]
      ..invokes['$agent/tasks/t-1 ▸ reject'] = []
      ..invokes['$agent/tasks/t-1 ▸ cancel'] = [];

    await s.dispatchAndWait(RetrieveTasksAction());
    expect(s.state.tasks.view, ['t-1']);

    await s.dispatchAndWait(RejectTaskAction('t-1', reason: 'not now'));
    expect(
      api.calls.last.toString(),
      contains('$agent/tasks/t-1 ▸ reject'),
    );
    expect(api.calls.last.args?['reason'], const VStr('not now'));

    await s.dispatchAndWait(CancelTaskAction('t-1'));
    expect(
      api.calls.last.toString(),
      contains('$agent/tasks/t-1 ▸ cancel'),
    );
  });

  Value record(String state) => Value.from({
    'state': state,
    'owner': 'user:olena',
    'ask': 'add ahu2',
    'plan': [
      {
        'n': 1,
        'invoke': 'wy/central/downstream/modbus/tcp',
        'action': 'add_device',
        'args': {'name': 'ahu2', 'unit': 3},
        'level': 'config',
        'approval': true,
        'check': 'now',
        'reason': 'the device the operator asked for',
      },
      {
        'n': 2,
        'set': 'wy/central/downstream/modbus/tcp/ahu2/sp',
        'value': 21.5,
        'level': 'write',
        'after': [1],
        'approval': true,
        'check': 'at_run',
        'warn': 'at the limit',
      },
      {
        'n': 3,
        'expect': 'wy/central/downstream/modbus/tcp/ahu2/sp',
        'equals': 21.5,
        'timeout_s': 10.0,
        'level': 'read',
        'after': [2],
        'approval': false,
        'check': 'now',
        'result': {'status': 'skipped', 'message': 'skipped: needs step 2'},
      },
    ],
    'plan_hash': 'the link says so',
    'log': ['asked by user:olena', 'model: I looked at line 2.'],
    'tokens': 12,
  });

  test('the record of a task is read through doc', () async {
    await withAgent();
    api.docs['$agent/tasks/t-1 ~state'] = record('awaiting_approval');

    await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));

    final t = s.state.tasks.table['t-1']!;
    expect(t.recorded, isTrue);
    expect(t.state, TaskState.awaitingApproval);
    expect(t.owner, 'user:olena');
    expect(t.log, hasLength(2));
    expect(t.plan, hasLength(3));
    final [a, b, c] = t.plan.toList();
    expect(
      (a.op, a.key, a.action),
      (
        'invoke',
        'wy/central/downstream/modbus/tcp',
        'add_device',
      ),
    );
    expect(a.args.unlock, {'name': 'ahu2', 'unit': 3});
    expect(
      (a.level, a.approval, a.reason),
      (
        'config',
        true,
        'the device the operator asked for',
      ),
    );
    expect((b.op, b.check, b.warn), ('set', 'at_run', 'at the limit'));
    expect(b.args.unlock, {'value': 21.5});
    expect(b.after, [1]);
    expect((c.op, c.seconds), ('expect', 10.0));
    expect(c.args.unlock, {'equals': 21.5});
    expect(c.result?.status, 'skipped');
    // the hash is made from the plan as read, not taken from the record
    expect(t.planHash, hasLength(64));
    expect(t.planHash, planHash(record('done')['plan']));
  });

  test('a gateway without doc: asked once, then the note stays', () async {
    await withAgent();
    api.errors['$agent/tasks/t-1 ~state'] = WyrmException.of(
      Status.invalidParameter,
      'unknown op "doc"',
    );

    await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));
    expect(s.state.assistant.docs, isFalse);
    await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));
    expect(api.calls.where((c) => c.op == 'doc'), hasLength(1));
  });

  test('a record the user may not read leaves the task as it is', () async {
    await withAgent();
    api.errors['$agent/tasks/t-1 ~state'] = WyrmException.of(
      Status.permissionDenied,
      'permission denied',
    );

    final status = await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));
    expect(status.originalError, isNull);
    expect(s.state.assistant.docs, isTrue);
    expect(s.state.tasks.table['t-1'], isNull);
  });

  group('approve through the gateway (ADR 0049 §2–4)', () {
    const task = '$agent/tasks/t-1';

    Future<void> waiting() async {
      await withAgent();
      api.docs['$task ~state'] = record('awaiting_approval');
      await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));
    }

    List<int> sent() => [
      for (final n
          in (api.calls.lastWhere((c) => c.action == 'approve').args!['steps']!
                  as VArray)
              .v)
        (n as VInt).v,
    ];

    test('every ticked step is sent by number, with the plan hash', () async {
      await waiting();
      api.invokes['$task ▸ approve'] = [
        Value.from({'task': 't-1', 'state': 'running'}),
      ];

      final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));

      expect(status.originalError, isNull);
      final call = api.calls.lastWhere((c) => c.action == 'approve');
      expect(call.key, task);
      expect(sent(), [1, 2]);
      expect(
        call.args?['plan'],
        VStr(planHash(record('awaiting_approval')['plan'])!),
      );
      // nothing of a step but its number goes out
      expect((call.args! as VMap).v.keys, unorderedEquals(['steps', 'plan']));
      // the record is read again after the approval
      expect(api.calls.where((c) => c.op == 'doc'), hasLength(2));
    });

    test('an unticked step is left out; ticking it again sends it', () async {
      await waiting();
      api.invokes['$task ▸ approve'] = [];
      s.dispatchSync(SetStepTickAction('t-1', 2, ticked: false));
      expect(s.state.assistant.unticked['t-1'], {2});

      await s.dispatchAndWait(ApproveTaskAction('t-1'));
      expect(sent(), [1]);
      // approved: the ticks of the task are forgotten
      expect(s.state.assistant.unticked['t-1'], isNull);

      s
        ..dispatchSync(SetStepTickAction('t-1', 2, ticked: false))
        ..dispatchSync(SetStepTickAction('t-1', 2, ticked: true));
      expect(s.state.assistant.unticked['t-1'], isNull);
    });

    test('a step that needs an unticked step is not sent', () async {
      await waiting();
      api.invokes['$task ▸ approve'] = [];
      s.dispatchSync(SetStepTickAction('t-1', 1, ticked: false));

      final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));

      // step 2 is after step 1: nothing is ticked, nothing is sent
      expect(status.originalError, isNull);
      expect(api.calls.where((c) => c.action == 'approve'), isEmpty);
    });

    test('a refused approval keeps the task waiting and says why', () async {
      await waiting();
      const why =
          'step 2 may be sent 290 s after this approval (the waits before '
          'it), and its approval is good for 300 s: leave it out and ask for '
          'it as a follow-up when this plan is done';
      api.errors['$task ▸ approve'] = WyrmException.of(
        Status.invalidParameter,
        why,
      );

      final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));

      // no error dialog: the task did not fail
      expect(status.originalError, isNull);
      expect(s.state.assistant.refusals['t-1'], why);
      expect(s.state.tasks.table['t-1']!.state, TaskState.awaitingApproval);

      // a changed tick is a new choice: the refusal is forgotten
      s.dispatchSync(SetStepTickAction('t-1', 2, ticked: false));
      expect(s.state.assistant.refusals['t-1'], isNull);
    });

    test('a step outside the grants refuses the same way', () async {
      await waiting();
      api.errors['$task ▸ approve'] = WyrmException.of(
        Status.permissionDenied,
        'step 1 needs config on wy/central/downstream/modbus/tcp; '
        'you have write',
      );

      final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));

      expect(status.originalError, isNull);
      expect(
        s.state.assistant.refusals['t-1'],
        contains('step 1 needs config'),
      );
    });

    test('any other failure of approve is an error', () async {
      await waiting();
      api.errors['$task ▸ approve'] = WyrmException.of(Status.timeout, '');

      final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));

      expect(status.originalError, isA<UserException>());
      expect(s.state.assistant.refusals['t-1'], isNull);
    });

    test(
      'a task of another site is not approved through this gateway',
      () async {
        await waiting();
        s.dispatchSync(ViewSiteAction('plant'));
        // the tables were emptied for the new site: the task is put back
        api.docs['$task ~state'] = record('awaiting_approval');
        s.dispatchSync(
          AddTasksAction(
            [agentTaskOf('t-1', record('awaiting_approval'))].lock,
          ),
        );

        await s.dispatchAndWait(ApproveTaskAction('t-1'));

        expect(api.calls.where((c) => c.action == 'approve'), isEmpty);
      },
    );
  });

  group('who signs what (approvalOf)', () {
    final plan = agentTaskOf('t', record('awaiting_approval')).plan;

    List<(bool?, String?, int?)> choices({
      Set<int> unticked = const {},
      bool decides = true,
      String? Function(String, String)? lacks,
    }) => [
      for (final c in approvalOf(
        plan,
        unticked: unticked.lock,
        decides: decides,
        lacks: lacks ?? (_, _) => null,
      ))
        (c.ticked, c.locked, c.needs),
    ];

    test('steps that need a human start ticked; a proof step has no tick', () {
      expect(choices(), [
        (true, null, null),
        (true, null, null),
        (null, null, null),
      ]);
    });

    test('an unticked step takes the steps after it with it', () {
      expect(choices(unticked: {1}), [
        (false, null, null),
        (false, null, 1),
        (null, null, 2),
      ]);
    });

    test('a step outside the grants is locked, by its request key', () {
      final asked = <String>[];
      final got = choices(
        lacks: (level, key) {
          asked.add('$level $key');
          return level == 'config' ? 'needs config' : null;
        },
      );
      expect(got.first, (false, 'needs config', null));
      expect(got[1], (false, null, 1));
      expect(asked, [
        'config wy/central/downstream/modbus/tcp/~act/add_device',
        'write wy/central/downstream/modbus/tcp/ahu2/sp/~set',
      ]);
    });

    test('a stranger to the task signs every step that changes something', () {
      final own = [
        for (final s in plan) s.copyWith(approval: false),
      ];
      List<bool?> ticks({required bool decides}) => [
        for (final c in approvalOf(
          own,
          unticked: const ISetConst({}),
          decides: decides,
          lacks: (_, _) => null,
        ))
          c.ticked,
      ];
      expect(ticks(decides: true), [null, null, null]);
      expect(ticks(decides: false), [true, true, null]);
    });
  });

  test('a run is followed: a new step or a step that ended reads the record '
      'again', () async {
    await withAgent();
    api.docs['$agent/tasks/t-1 ~state'] = record('running');
    s.dispatchSync(SetSelectedTaskAction('t-1'));
    Future<void> val(Map<String, Object?> v) async {
      api.subs['$agent/tasks/*']!.add(
        ValSample('$agent/tasks/t-1', Sample(Value.from(v), t: 1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    int reads() => api.calls.where((c) => c.op == 'doc').length;

    await val({'state': 'running', 'step': 1, 'of': 3});
    expect(reads(), 1);
    expect(s.state.tasks.table['t-1']!.state, TaskState.running);

    // the same value again: nothing moved
    await val({'state': 'running', 'step': 1, 'of': 3});
    expect(reads(), 1);

    // step 1 ended (the public value says so without any text)
    await val({
      'state': 'running',
      'step': 1,
      'of': 3,
      'last': {'n': 1, 'ok': true, 'result': 'ok'},
    });
    expect(reads(), 2);

    // step 2 started
    await val({
      'state': 'running',
      'step': 2,
      'of': 3,
      'last': {'n': 1, 'ok': true, 'result': 'ok'},
    });
    expect(reads(), 3);

    // a task that is not on screen is not read
    await val({'state': 'running', 'step': 2, 'of': 3});
    s.dispatchSync(SetSelectedTaskAction(null));
    final before = reads();
    await val({'state': 'done', 'step': 3, 'of': 3});
    expect(reads(), before);
    expect(s.state.tasks.table['t-1']!.state, TaskState.done);
  });

  test('the plan as a file is the wyrm-agent run format', () {
    final file = planFile(agentTaskOf('t-1', record('done')));
    expect(file['about'], 'add ahu2');
    expect(file['steps'], [
      {
        'invoke': 'wy/central/downstream/modbus/tcp',
        'action': 'add_device',
        'args': {'name': 'ahu2', 'unit': 3},
      },
      {'set': 'wy/central/downstream/modbus/tcp/ahu2/sp', 'value': 21.5},
      {
        'expect': 'wy/central/downstream/modbus/tcp/ahu2/sp',
        'equals': 21.5,
        'timeout_s': 10.0,
      },
    ]);
  });

  test('the questions of a record: options, kinds and answers', () {
    final t = agentTaskOf(
      't-1',
      Value.from({
        'state': 'awaiting_answer',
        'questions': [
          {
            'id': 'q1',
            'text': 'Which unit?',
            'options': [
              {'id': 'u3', 'label': 'Slave ID 3', 'detail': 'answers'},
              {'id': 'u4', 'label': 'Slave ID 4', 'detail': ''},
            ],
            'multiple': false,
            'free_text': true,
          },
          {
            'id': 'q2',
            'text': 'Which points?',
            'options': <Object?>[],
            'multiple': true,
            'free_text': false,
            'answer': ['supply', 'fan'],
          },
          {'id': 'q3', 'text': 'Why?', 'answer': 'because'},
          {'id': 'q4', 'text': 'Left open', 'answer': <Object?>[]},
        ],
      }),
    );
    expect(t.state, TaskState.awaitingAnswer);
    final [a, b, c, d] = t.questions.toList();
    expect(
      (a.id, a.text, a.multiple, a.freeText, a.answered),
      (
        'q1',
        'Which unit?',
        false,
        true,
        false,
      ),
    );
    expect(
      [for (final o in a.options) (o.id, o.label, o.detail)],
      [('u3', 'Slave ID 3', 'answers'), ('u4', 'Slave ID 4', '')],
    );
    expect(
      (b.multiple, b.answered, b.picked.unlock),
      (
        true,
        true,
        ['supply', 'fan'],
      ),
    );
    expect((c.answered, c.words), (true, 'because'));
    expect((d.answered, d.picked.unlock, d.words), (true, <String>[], null));
  });

  test('an answer is sent only for a task that waits for one', () async {
    await withAgent();
    api.docs['$agent/tasks/t-1 ~state'] = record('awaiting_approval');
    await s.dispatchAndWait(RetrieveTaskRecordAction('t-1'));

    await s.dispatchAndWait(AnswerTaskAction('t-1', text: 'unit 4'));

    expect(api.calls.where((c) => c.action == 'answer'), isEmpty);
  });

  test('a follow-up ask names its parent and keeps the draft', () async {
    await withAgent();
    api.invokes['$agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    s.dispatchSync(SetDraftAction('something else'));

    await s.dispatchAndWait(AskAgentAction(text: 'do step 2', parent: 't-1'));

    final call = api.calls.lastWhere((c) => c.action == 'ask');
    expect(call.args?['task'], const VStr('do step 2'));
    expect(call.args?['parent'], const VStr('t-1'));
    expect(s.state.tasks.table['t-2']!.parent, 't-1');
    expect(s.state.assistant.draft, 'something else');
  });
}
