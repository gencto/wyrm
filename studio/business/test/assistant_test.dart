import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/ask_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/tasks/actions/approve_task_action.dart';
import 'package:business/redux/tasks/actions/cancel_task_action.dart';
import 'package:business/redux/tasks/actions/reject_task_action.dart';
import 'package:business/redux/tasks/actions/retrieve_task_record_action.dart';
import 'package:business/redux/tasks/actions/retrieve_tasks_action.dart';
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

  test('approve refuses until the gateway signs approvals', () async {
    await withAgent();
    final status = await s.dispatchAndWait(ApproveTaskAction('t-1'));
    expect(status.originalError, isA<UserException>());
    expect(api.calls.where((c) => c.action == 'approve'), isEmpty);
  });
}
