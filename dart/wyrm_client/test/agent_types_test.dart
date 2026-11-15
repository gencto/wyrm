// The decoders of the agent link's shapes (a task's record, its public
// value, the stream rows) and the typed agent calls, without a broker.
// Shapes as `links/agent` writes them (`Task::to_value`, `public_value`,
// `PlanOp::to_value`); then malformed ones.

import 'dart:async';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

Matcher _decodeError(String path) =>
    isA<DecodeError>().having((e) => e.path, 'path', path);

/// A gateway that records each request and answers it with [answer]: a
/// list of frames (events, then the final one).
class _Conn implements FrameTransport {
  final _in = StreamController<Value>();
  final sent = <FrameRequest>[];
  List<Map<String, Value>> Function(FrameRequest r) answer = (_) => [
    {'ok': const VBool(true)},
  ];

  @override
  Stream<Value> get incoming => _in.stream;

  @override
  void send(FrameRequest request) {
    sent.add(request);
    for (final f in answer(request)) {
      scheduleMicrotask(() => _in.add(VMap({'id': VInt(request.id), ...f})));
    }
  }

  @override
  Future<void> close() => _in.close();
}

const _node = 'wy/s/downstream/m/p';

final _plan = VArray([
  VMap({
    'n': const VInt(1),
    'set': const VStr(_node),
    'value': const VFloat(42.5),
    'level': const VStr('write'),
    'approval': const VBool(true),
    'check': const VStr('now'),
    'warn': const VStr('at the limit'),
    'result': VMap({
      'status': const VStr('ok'),
      'message': const VStr('done'),
      'time': const VInt(1700000000),
    }),
  }),
  VMap({
    'n': const VInt(2),
    'invoke': const VStr('wy/s/downstream/m'),
    'action': const VStr('reset'),
    'args': VMap({'all': const VBool(true)}),
    'level': const VStr('config'),
    'after': VArray([const VInt(1)]),
    'approval': const VBool(true),
    'check': const VStr('at_run'),
  }),
  VMap({
    'n': const VInt(3),
    'expect': const VStr(_node),
    'min': const VInt(40),
    'max': const VFloat(45.0),
    'timeout_s': const VFloat(10.0),
    'level': const VStr('read'),
    'approval': const VBool(false),
    'check': const VStr('now'),
  }),
  VMap({
    'n': const VInt(4),
    'wait': const VStr(_node),
    'timeout_s': const VFloat(5.0),
    'level': const VStr('read'),
    'approval': const VBool(false),
    'check': const VStr('now'),
  }),
  VMap({
    'n': const VInt(5),
    'sleep_s': const VFloat(2.0),
    'level': const VStr('read'),
    'approval': const VBool(false),
    'check': const VStr('now'),
  }),
]);

final _record = VMap({
  'state': const VStr('awaiting_approval'),
  'owner': const VStr('user:olena'),
  'ask': const VStr('set the point'),
  'plan': _plan,
  'plan_hash': VStr(planHash(_plan)!),
  'questions': VArray([
    VMap({
      'id': const VStr('q1'),
      'text': const VStr('Which group?'),
      'options': VArray([
        VMap({
          'id': const VStr('g0'),
          'label': const VStr('Group 0'),
          'detail': const VStr(''),
        }),
      ]),
      'multiple': const VBool(false),
      'free_text': const VBool(true),
      'answer': VArray([const VStr('g0')]),
    }),
  ]),
  'suggestions': VArray([
    VMap({
      'id': const VStr('s1'),
      'label': const VStr('Same for more units'),
      'detail': const VStr(''),
      'changes': const VInt(2),
      'step': const VInt(1),
      'rows': VArray([
        VMap({
          'key': const VStr('wy/s/downstream/m/u4'),
          'label': const VStr('unit 4'),
          'detail': const VStr('ahu'),
        }),
      ]),
    }),
  ]),
  'findings': VArray([
    VMap({
      'key': const VStr('wy/s/downstream/m/plc1'),
      'label': const VStr('plc1'),
      'detail': const VStr('4 of 5 good'),
    }),
  ]),
  'findings_refused': VMap({
    'rights_expired': const VInt(2),
    'limit': const VInt(0),
    'a_new_reason': const VInt(1),
  }),
  'parent': const VStr('t0'),
  'context': VArray([const VStr(_node)]),
  'step': const VInt(1),
  'log': VArray([const VStr('planned')]),
  'tokens': const VInt(1234),
});

void main() {
  group('AgentTaskRecord', () {
    test('decodes every field the link writes', () {
      final r = AgentTaskRecord.fromValue(_record);
      expect(r.state, AgentTaskState.awaitingApproval);
      expect(
        (r.owner, r.ask, r.step, r.tokens),
        ('user:olena', 'set the point', 1, 1234),
      );
      expect(r.planHash, r.shownPlanHash);
      expect(r.shownPlanHash, planHash(_plan));
      expect(r.parent, 't0');
      expect(r.replacedBy, isNull);
      expect(r.context, [_node]);
      expect(r.log, ['planned']);
      expect(r.findingsRefused, {AgentFindingRefusal.rightsExpired: 2});
      expect(r.findings.single.detail, '4 of 5 good');
      final s = r.suggestions.single;
      expect(
        (s.changes, s.step, s.rows.single.key),
        (2, 1, 'wy/s/downstream/m/u4'),
      );
      final q = r.questions.single;
      expect((q.id, q.freeText, q.options.single.id), ('q1', true, 'g0'));
      expect(q.answer, const AgentAnswer.options(['g0']));
    });

    test('plan steps of every kind', () {
      final p = AgentTaskRecord.fromValue(_record).plan;
      expect(p.map((s) => s.kind), [
        AgentStepKind.set,
        AgentStepKind.invoke,
        AgentStepKind.expect,
        AgentStepKind.wait,
        AgentStepKind.sleep,
      ]);
      final set = p[0];
      expect(
        (set.n, set.node, set.value, set.level),
        (1, _node, const VFloat(42.5), Perm.write),
      );
      expect(
        (set.approval, set.check, set.warn),
        (true, AgentStepCheck.now, 'at the limit'),
      );
      expect(
        set.result,
        const AgentStepResult(
          status: AgentStepStatus.ok,
          message: 'done',
          time: 1700000000,
        ),
      );
      final inv = p[1];
      expect(
        (inv.action, inv.args, inv.check),
        ('reset', VMap({'all': const VBool(true)}), AgentStepCheck.atRun),
      );
      expect(inv.after, [1]);
      expect(inv.level, Perm.config);
      final exp = p[2];
      expect(
        (exp.min, exp.max, exp.seconds, exp.changes),
        (40.0, 45.0, 10.0, false),
      );
      expect(p[3].seconds, 5.0);
      expect((p[4].node, p[4].seconds), (null, 2.0));
    });

    test('optional fields may be absent; required ones may not', () {
      final minimal = VMap({
        'state': const VStr('done'),
        'owner': const VStr('user:olena'),
        'ask': const VStr('x'),
        'plan': VArray(const []),
        'plan_hash': VStr(planHash(VArray(const []))!),
        'step': const VInt(0),
        'log': VArray(const []),
        'tokens': const VInt(0),
      });
      final r = AgentTaskRecord.fromValue(minimal);
      expect(r.plan, isEmpty);
      expect(r.suggestions, isEmpty);
      expect(r.findingsRefused, isEmpty);
      expect(r.shownPlanHash, r.planHash);
      expect(
        (r.replacedBy, r.review, r.reviewing, r.error),
        (null, null, false, null),
      );
      for (final k in [
        'owner',
        'ask',
        'plan',
        'plan_hash',
        'step',
        'log',
        'tokens',
      ]) {
        expect(
          () => AgentTaskRecord.fromValue(VMap({...minimal.v}..remove(k))),
          throwsA(_decodeError('AgentTaskRecord.$k')),
          reason: k,
        );
      }
    });

    test('a malformed record names the field', () {
      final second = switch (_plan.v[1]) {
        VMap(:final v) => v,
        _ => const <String, Value>{},
      };
      VMap withStep(Map<String, Value> step) => VMap({
        ..._record.v,
        'plan': VArray([
          _plan.v[0],
          VMap({...second, ...step}),
        ]),
      });
      expect(
        () => AgentTaskRecord.fromValue(
          VMap({..._record.v, 'state': const VStr('paused')}),
        ),
        throwsA(_decodeError('AgentTaskRecord.state')),
      );
      expect(
        () =>
            AgentTaskRecord.fromValue(withStep({'level': const VStr('admin')})),
        throwsA(_decodeError('AgentTaskRecord.plan[1].level')),
      );
      expect(
        () =>
            AgentTaskRecord.fromValue(withStep({'check': const VStr('later')})),
        throwsA(_decodeError('AgentTaskRecord.plan[1].check')),
      );
      expect(
        () => AgentTaskRecord.fromValue(
          withStep({
            'result': VMap({'status': const VStr('partly')}),
          }),
        ),
        throwsA(_decodeError('AgentTaskRecord.plan[1].result.status')),
      );
      expect(
        () => AgentTaskRecord.fromValue(
          VMap({
            ..._record.v,
            'plan': VArray([
              VMap({'n': const VInt(1), 'level': const VStr('read')}),
            ]),
          }),
        ),
        throwsA(_decodeError('AgentTaskRecord.plan[0]')),
      );
      expect(
        () => AgentTaskRecord.fromValue(
          VMap({
            ..._record.v,
            'findings': VArray([
              VMap({'label': const VStr('nowhere')}),
            ]),
          }),
        ),
        throwsA(_decodeError('AgentTaskRecord.findings[0].key')),
      );
    });
  });

  group('AgentTaskValue', () {
    test('decodes the public value', () {
      final v = AgentTaskValue.fromValue(
        VMap({
          'state': const VStr('running'),
          'step': const VInt(2),
          'of': const VInt(4),
          'last': VMap({
            'n': const VInt(2),
            'ok': const VBool(false),
            'result': const VStr('failed'),
          }),
          'suggestions': const VInt(1),
          'reviewing': const VBool(true),
          'replaced_by': const VStr('t9'),
        }),
      );
      expect(
        (v.state, v.step, v.of, v.suggestions, v.findings),
        (AgentTaskState.running, 2, 4, 1, 0),
      );
      expect(
        v.last,
        const AgentLastStep(n: 2, ok: false, result: AgentStepStatus.failed),
      );
      expect((v.reviewing, v.replacedBy), (true, 't9'));
      expect(
        () => AgentTaskValue.fromValue(VMap({'state': const VInt(2)})),
        throwsA(_decodeError('AgentTaskValue.state')),
      );
      expect(
        () => AgentTaskValue.fromValue(
          VMap({'state': const VStr('done'), 'step': const VInt(1)}),
        ),
        throwsA(_decodeError('AgentTaskValue.of')),
      );
    });
  });

  group('AgentReply', () {
    test('state rows, event rows, an unknown event is skipped', () {
      expect(
        AgentReply.fromValue(
          VMap({'task': const VStr('t1'), 'state': const VStr('planning')}),
        ),
        const AgentReply.state(task: 't1', state: AgentTaskState.planning),
      );
      expect(
        AgentReply.fromValue(
          VMap({
            'task': const VStr('t1'),
            'event': const VStr('tool'),
            'text': const VStr('read (error)'),
          }),
        ),
        const AgentReply.event(
          task: 't1',
          kind: AgentEventKind.tool,
          text: 'read (error)',
        ),
      );
      expect(
        AgentReply.fromValue(
          VMap({
            'task': const VStr('t1'),
            'event': const VStr('thinking'),
            'text': const VStr(''),
          }),
        ),
        isNull,
      );
      expect(
        () => AgentReply.fromValue(VMap({'state': const VStr('planning')})),
        throwsA(_decodeError('AgentReply.task')),
      );
    });

    test('answers: option ids or words', () {
      expect(
        AgentAnswer.fromValue(const VStr('my words')),
        const AgentAnswer.text('my words'),
      );
      expect(
        const AgentAnswer.options(['a', 'b']).toValue(),
        VArray([const VStr('a'), const VStr('b')]),
      );
      expect(
        () => AgentAnswer.fromValue(const VInt(1)),
        throwsA(_decodeError('AgentAnswer')),
      );
    });
  });

  group('typed calls', () {
    const agent = 'wy/s/downstream/agent';
    const task = '$agent/tasks/t1';

    test('agentAsk sends its args and decodes the rows', () async {
      final conn = _Conn()
        ..answer = (r) => [
          {
            'event': VMap({
              'type': const VStr('value'),
              'v': VMap({
                'task': const VStr('t1'),
                'state': const VStr('planning'),
              }),
            }),
          },
          {
            'event': VMap({
              'type': const VStr('value'),
              'v': VMap({
                'task': const VStr('t1'),
                'event': const VStr('text'),
                'text': const VStr('hi'),
              }),
            }),
          },
          {
            'ok': const VBool(true),
            'result': VMap({
              'task': const VStr('t1'),
              'state': const VStr('awaiting_approval'),
            }),
          },
        ];
      final c = FrameClient(conn);
      final rows = await c
          .agentAsk(agent, 'do it', parent: 't0', context: [_node])
          .toList();
      expect(rows, [
        const AgentReply.state(task: 't1', state: AgentTaskState.planning),
        const AgentReply.event(
          task: 't1',
          kind: AgentEventKind.text,
          text: 'hi',
        ),
        const AgentReply.state(
          task: 't1',
          state: AgentTaskState.awaitingApproval,
        ),
      ]);
      final r = conn.sent.single;
      expect((r.op, r.key, r.action), (FrameOp.invoke, agent, 'ask'));
      expect(
        r.args,
        VMap({
          'task': const VStr('do it'),
          'parent': const VStr('t0'),
          'context': VArray([const VStr(_node)]),
        }),
      );
      await c.close();
    });

    test('agentAnswer, agentApprove and agentRecord', () async {
      final conn = _Conn();
      final c = FrameClient(conn);
      conn.answer = (r) => [
        {
          'ok': const VBool(true),
          'result': VMap({
            'task': const VStr('t1'),
            'state': const VStr('running'),
          }),
        },
      ];
      final s = await c.agentApprove(task, steps: [1, 3], plan: 'h1');
      expect(s?.state, AgentTaskState.running);
      expect(
        conn.sent.last.args,
        VMap({
          'steps': VArray([const VInt(1), const VInt(3)]),
          'plan': const VStr('h1'),
        }),
      );
      await c
          .agentAnswer(
            task,
            answers: {
              'q1': const AgentAnswer.options(['a']),
              'q2': const AgentAnswer.text('my words'),
            },
          )
          .drain<void>();
      expect(
        conn.sent.last.args,
        VMap({
          'answers': VMap({
            'q1': VArray([const VStr('a')]),
            'q2': const VStr('my words'),
          }),
        }),
      );
      conn.answer = (r) => [
        {'ok': const VBool(true), 'result': _record},
      ];
      final rec = await c.agentRecord(task);
      expect(rec.state, AgentTaskState.awaitingApproval);
      expect(
        (conn.sent.last.op, conn.sent.last.suffix),
        (FrameOp.doc, DocSuffix.state),
      );
      await c.close();
    });

    test('a malformed reply is invalid_message naming the field', () async {
      final conn = _Conn()
        ..answer = (r) => [
          {
            'ok': const VBool(true),
            'result': VMap({'state': const VStr('nope')}),
          },
        ];
      final c = FrameClient(conn);
      await expectLater(
        c.agentRecord(task),
        throwsA(
          isA<WyrmException>()
              .having((e) => e.status.known, 'status', Status.invalidMessage)
              .having(
                (e) => e.message,
                'message',
                contains('AgentTaskRecord.state'),
              ),
        ),
      );
      await expectLater(
        c.agentAsk(agent, 'x').toList(),
        throwsA(
          isA<WyrmException>().having(
            (e) => e.message,
            'message',
            contains('AgentReply.task'),
          ),
        ),
      );
      await c.close();
    });
  });
}
