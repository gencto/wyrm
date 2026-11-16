// The agent link's old call shapes (deprecated shims, kept for one
// release) and the plan hash, without a broker. The typed calls are in
// agent_types_test.dart.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A gateway that records each frame and answers it with [answer].
class _Conn implements FrameTransport {
  final _in = StreamController<Value>();
  final sent = <Map<String, Value>>[];
  Map<String, Value> Function(Map<String, Value> frame) answer = (_) => {'ok': const VBool(true)};

  @override
  Stream<Value> get incoming => _in.stream;

  @override
  void send(FrameRequest request) {
    final frame = request.toValue().v;
    sent.add(frame);
    final reply = answer(frame);
    scheduleMicrotask(() => _in.add(VMap({'id': VInt(request.id), ...reply})));
  }

  @override
  Future<void> close() => _in.close();
}

void main() {
  test('the plan hash is the one the agent link and the gateway make', () {
    // the same vector as links/agent (tools tests) and crates/wyrm-gateway (approve tests)
    final step = <String, Value>{
      'n': const VInt(1),
      'set': const VStr('wy/s/downstream/m/p'),
      'value': const VFloat(1.0),
      'level': const VStr('write'),
    };
    const want = '08900496afc130ee83048251cb224b679cbfd06491270fa67d386c7dcc6cd60d';
    expect(planHash(VArray([VMap(step)])), want);
    // what is said about a step is no part of it
    final told = VMap({
      ...step,
      'approval': const VBool(true),
      'check': const VStr('at_run'),
      'warn': const VStr('at the limit'),
      'model_warn': const VStr('read by another loop'),
      'reason': const VStr('because'),
      'result': VMap({'status': const VStr('ok')}),
    });
    expect(planHash(VArray([told])), want);
    // what it does is: the value, the level, the order, what it needs
    for (final other in [
      VMap({...step, 'value': const VFloat(2.0)}),
      VMap({...step, 'level': const VStr('config')}),
      VMap({...step, 'set': const VStr('wy/s/downstream/m/q')}),
      VMap({...step, 'after': VArray([const VInt(1)])}),
    ]) {
      expect(planHash(VArray([other])), isNot(want));
    }
    expect(planHash(VArray([VMap(step), VMap(step)])), isNot(want));
    expect(planHash(const VNull()), isNull);
    expect(planHash(VArray([const VStr('step')])), isNull);
  });

  test('doc, ask, answer and approve go out in their shapes', () async {
    final conn = _Conn();
    final c = FrameClient(conn);
    conn.answer = (f) => {
          'ok': const VBool(true),
          'result': VMap({'task': const VStr('t1'), 'state': const VStr('done')}),
        };
    const task = 'wy/s/downstream/agent/tasks/t1';

    final rec = await c.doc(task, '~state');
    expect(rec['state'], const VStr('done'));
    expect(conn.sent.last['op'], const VStr('doc'));
    expect(conn.sent.last['suffix'], const VStr('~state'));

    final approved = await c.agentApprove(task, steps: [1, 3], plan: 'h1');
    expect(approved, const AgentReply.state(task: 't1', state: AgentTaskState.done));
    expect(conn.sent.last['op'], const VStr('invoke'));
    expect(conn.sent.last['action'], const VStr('approve'));
    expect(
        conn.sent.last['args'],
        VMap({
          'steps': VArray([const VInt(1), const VInt(3)]),
          'plan': const VStr('h1'),
        }));

    await c.agentAsk('wy/s/downstream/agent', 'do it', parent: 't0', context: ['wy/s/downstream/m']).drain<void>();
    expect(
        conn.sent.last['args'],
        VMap({
          'task': const VStr('do it'),
          'parent': const VStr('t0'),
          'context': VArray([const VStr('wy/s/downstream/m')]),
        }));
    await c.agentAsk('wy/s/downstream/agent', 'do it').drain<void>();
    expect(conn.sent.last['args'], VMap({'task': const VStr('do it')}));

    await c.agentAnswer(task, answers: {
      'q1': const AgentAnswer.options(['a']),
      'q2': const AgentAnswer.text('my words'),
    }).drain<void>();
    expect(conn.sent.last['action'], const VStr('answer'));
    expect(
        conn.sent.last['args'],
        VMap({
          'answers': VMap({
            'q1': VArray([const VStr('a')]),
            'q2': const VStr('my words'),
          }),
        }));
    await c.close();
  });

  test('a picked suggestion is a follow-up ask', () async {
    final record = AgentTaskRecord.fromValue(VMap({
      'state': const VStr('failed'),
      'owner': const VStr('user:olena'),
      'ask': const VStr('x'),
      'plan': VArray(const []),
      'plan_hash': VStr(planHash(VArray(const []))!),
      'step': const VInt(0),
      'log': VArray(const []),
      'tokens': const VInt(0),
      'suggestions': VArray([
        VMap({
          'id': const VStr('s1'),
          'label': const VStr('Try slave id 4'),
          'detail': const VStr('3 is used by ahu-old'),
          'changes': const VInt(1),
          'step': const VInt(2),
        }),
        VMap({
          'id': const VStr('s2'),
          'label': const VStr('Same for more units'),
          'detail': const VStr(''),
          'changes': const VInt(2),
          'rows': VArray([
            VMap({'key': const VStr('wy/s/downstream/m/u4'), 'label': const VStr('unit 4'), 'detail': const VStr('ahu')}),
            VMap({'key': const VStr('wy/s/downstream/m/u5'), 'label': const VStr('unit 5'), 'detail': const VStr('')}),
          ]),
        }),
      ]),
    }));
    final s = record.suggestions;
    expect(s[0].ask(), 'Try slave id 4. 3 is used by ahu-old');
    expect(s[1].ask([s[1].rows[1]]), 'Same for more units\nFor: unit 5');

    // picking one is a follow-up ask: its text, the parent, the ticked rows as context
    final conn = _Conn();
    final c = FrameClient(conn);
    await c.agentAskSuggestion('wy/s/downstream/agent', 't1-1', s[1], rows: [s[1].rows[0]]).drain<void>();
    expect(
        conn.sent.last['args'],
        VMap({
          'task': const VStr('Same for more units\nFor: unit 4'),
          'parent': const VStr('t1-1'),
          'context': VArray([const VStr('wy/s/downstream/m/u4')]),
        }));
    await c.agentAskSuggestion('wy/s/downstream/agent', 't1-1', s[0]).drain<void>();
    expect(
        conn.sent.last['args'],
        VMap({'task': const VStr('Try slave id 4. 3 is used by ahu-old'), 'parent': const VStr('t1-1')}));
    await c.close();
  });

  test('an older gateway answers doc with unknown op', () async {
    final conn = _Conn();
    final c = FrameClient(conn);
    conn.answer = (f) => {
          'ok': const VBool(false),
          'error': VMap({
            'status': VInt(Status.invalidParameter.code),
            'message': const VStr('unknown op "doc"'),
          }),
        };
    await expectLater(
        c.doc('wy/s/x', '~state'), throwsA(isA<WyrmException>().having(isUnknownOp, 'unknown op', isTrue)));
    conn.answer = (f) => {
          'ok': const VBool(false),
          'error': VMap({
            'status': VInt(Status.invalidParameter.code),
            'message': const VStr('suffix: ~state or ~def required'),
          }),
        };
    await expectLater(
        c.doc('wy/s/x', 'state'), throwsA(isA<WyrmException>().having(isUnknownOp, 'unknown op', isFalse)));
    await c.close();
  });
}
