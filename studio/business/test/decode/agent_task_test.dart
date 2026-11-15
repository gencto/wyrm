import 'package:business/wyrm/decode/agent_config.dart';
import 'package:business/wyrm/decode/agent_task.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/agent_config.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_mode.dart';
import 'package:models/finding_refusal.dart';
import 'package:models/step_check.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_status.dart';
import 'package:models/task_event_kind.dart';
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../support/agent_records.dart';

/// The agent link's task and settings as Studio's domain (the record's
/// layout: `links/agent/src/lib.rs`, module doc). Each wire value is read
/// once, by `wyrm_client`'s decoders, and a value that is not one names
/// its field.
void main() {
  group('a task record', () {
    test('each step kind, its check, level, arguments and result', () {
      final t = taskOf(
        taskRecord({
          'state': 'running',
          'owner': 'user:olena',
          'ask': 'add ahu2',
          'plan': [
            {
              'n': 1,
              'invoke': 'wy/c/downstream/m/tcp',
              'action': 'add_device',
              'args': {
                'name': 'ahu2',
                'unit': 3,
                'opts': {'poll_ms': 500},
              },
              'level': 'config',
              'approval': true,
              'check': 'now',
              'result': {
                'status': 'failed',
                'message': 'out_of_range: 3 is taken',
                'time': 1794100000,
              },
            },
            {
              'n': 2,
              'set': 'wy/c/downstream/m/tcp/ahu2/sp',
              'value': 21.5,
              'level': 'write',
              'after': [1],
              'check': 'at_run',
            },
            {
              'n': 3,
              'expect': 'wy/c/downstream/m/tcp/ahu2/sp',
              'equals': 21.5,
              'timeout_s': 10,
              'level': 'read',
            },
            {'n': 4, 'wait': 'wy/c/downstream/m/tcp/ahu2', 'level': 'read'},
            {'n': 5, 'sleep_s': 2.5, 'level': 'read'},
          ],
          'log': [
            'asked by user:olena',
            'model: I read line 2.',
            'approved by user:olena, 1 step(s) left out',
            'failed: unit 3 is taken',
          ],
          'findings_refused': {'rights_expired': 2, 'not_a_reason': 1},
        }),
      );
      expect(t.state, TaskState.running);
      expect(
        [for (final s in t.plan) (s.n, s.kind, s.level, s.check)],
        [
          (1, StepKind.invoke, Perm.config, StepCheck.now),
          (2, StepKind.set, Perm.write, StepCheck.atRun),
          (3, StepKind.expect, Perm.read, StepCheck.now),
          (4, StepKind.wait, Perm.read, StepCheck.now),
          (5, StepKind.sleep, Perm.read, StepCheck.now),
        ],
      );
      expect(t.plan[0].args.unlock, {
        'name': 'ahu2',
        'unit': 3,
        'opts': {'poll_ms': 500},
      });
      expect(t.plan[1].args.unlock, {'value': 21.5});
      expect(t.plan[2].args.unlock, {'equals': 21.5});
      expect((t.plan[2].seconds, t.plan[4].seconds), (10.0, 2.5));
      expect(t.plan[4].key, '');
      final r = t.plan[0].result!;
      expect((r.status, r.code), (StepStatus.failed, 'out_of_range'));
      expect(r.time, DateTime.fromMillisecondsSinceEpoch(1794100000 * 1000));
      // a reason this client does not know is left out
      expect(t.findingsRefused.unlock, {FindingRefusal.rightsExpired: 2});
      expect(t.approvedBy, 'approved by olena, 1 step(s) left out');
      expect(
        [for (final e in t.told) (e.kind, e.text)],
        [
          (TaskEventKind.ask, 'add ahu2'),
          (TaskEventKind.text, 'I read line 2.'),
          (TaskEventKind.note, 'approved by user:olena, 1 step(s) left out'),
          (TaskEventKind.error, 'unit 3 is taken'),
        ],
      );
    });

    test("the plan's hash is made from the plan as read, not the link's", () {
      final plan = [
        {'n': 1, 'set': 'wy/c/downstream/m/a', 'value': 1, 'level': 'write'},
      ];
      final told = taskOf(
        taskRecord({
          'state': 'awaiting_approval',
          'plan': plan,
          'plan_hash': 'what the link says',
        }),
      );
      expect(told.planHash, planHash(Value.from(plan)));
    });

    test('a field of another type names itself, never an empty task', () {
      expect(
        agentTaskOf('t', taskRecord({'state': 'done', 'tokens': 'many'})),
        isA<Invalid<AgentTask>>().having(
          (i) => i.field,
          'field',
          'AgentTaskRecord.tokens',
        ),
      );
      expect(
        agentTaskOf(
          't',
          taskRecord({
            'state': 'done',
            'plan': [
              {'n': 1, 'set': 'wy/c/a', 'value': 1, 'level': 'root'},
            ],
          }),
        ),
        isA<Invalid<AgentTask>>(),
      );
    });
  });

  group("a task's public value", () {
    test('reads its numbers; without `of` it is not one', () {
      expect(
        agentTaskValueOf(
          Value.from({
            'state': 'failed',
            'step': 2,
            'of': 3,
            'last': {'n': 2, 'ok': false, 'result': 'failed'},
            'reviewing': true,
            'replaced_by': 't-9',
          }),
        ),
        isA<Valid<AgentTaskValue>>()
            .having((v) => v.value.state, 'state', AgentTaskState.failed)
            .having((v) => v.value.last?.n, 'last', 2)
            .having((v) => v.value.replacedBy, 'replacedBy', 't-9'),
      );
      expect(
        agentTaskValueOf(Value.from({'state': 'running', 'step': 1})),
        isA<Invalid<AgentTaskValue>>().having(
          (i) => i.field,
          'field',
          'AgentTaskValue.of',
        ),
      );
    });
  });

  group("the agent's settings", () {
    test('each setting, typed', () {
      expect(
        agentConfigOf({
          'model': const VStr('claude-sonnet-5-5'),
          'require_approval': const VStr('config'),
          'allowed_prefixes': Value.from(['wy/c/downstream/m']),
          'budget_tokens_day': const VInt(1000000),
          'api_key_ref': const VStr('anthropic_api_key'),
          'api_base': const VStr('https://api.anthropic.com/v1'),
          'other': const VBool(true),
        }),
        Valid(
          AgentConfig(
            model: 'claude-sonnet-5-5',
            approval: ApprovalMode.config,
            prefixes: const ['wy/c/downstream/m'].lock,
            budgetTokensDay: 1000000,
            apiKeyRef: 'anthropic_api_key',
            apiBase: 'https://api.anthropic.com/v1',
          ),
        ),
      );
      expect(
        agentConfigOf({
          'api_base': const VStr('https://api.anthropic.com/v1'),
        }).orWarn('t')?.sentTo,
        'api.anthropic.com',
      );
      expect(agentConfigOf(const {}), const Valid(AgentConfig()));
    });

    test('a mode the link does not have names its setting', () {
      expect(
        agentConfigOf({'require_approval': const VStr('always')}),
        isA<Invalid<AgentConfig>>().having(
          (i) => i.field,
          'field',
          'agent cfg.require_approval',
        ),
      );
    });

    test('the secret names are a list of names', () {
      expect(
        secretNamesOf(Value.from(['a', 'b'])),
        Valid({'a', 'b'}.lock),
      );
      expect(secretNamesOf(Value.from([1])), isA<Invalid<ISet<String>>>());
      expect(secretNamesOf(const VStr('a')), isA<Invalid<ISet<String>>>());
    });
  });
}
