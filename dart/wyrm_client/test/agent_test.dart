// The agent link's call shapes and the plan hash, without a broker.

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
  void send(Map<String, Value> frame) {
    sent.add(frame);
    final reply = answer(frame);
    scheduleMicrotask(() => _in.add(VMap({'id': frame['id']!, ...reply})));
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
    conn.answer = (f) => {'ok': const VBool(true), 'result': VMap({'state': const VStr('done')})};
    const task = 'wy/s/downstream/agent/tasks/t1';

    final rec = await c.doc(task, '~state');
    expect(rec['state'], const VStr('done'));
    expect(conn.sent.last['op'], const VStr('doc'));
    expect(conn.sent.last['suffix'], const VStr('~state'));

    await c.approveTask(task, steps: [1, 3], plan: 'h1');
    expect(conn.sent.last['op'], const VStr('invoke'));
    expect(conn.sent.last['action'], const VStr('approve'));
    expect(
        conn.sent.last['args'],
        VMap({
          'steps': VArray([const VInt(1), const VInt(3)]),
          'plan': const VStr('h1'),
        }));

    await c.askAgent('wy/s/downstream/agent', 'do it', parent: 't0', context: ['wy/s/downstream/m']).drain<void>();
    expect(
        conn.sent.last['args'],
        VMap({
          'task': const VStr('do it'),
          'parent': const VStr('t0'),
          'context': VArray([const VStr('wy/s/downstream/m')]),
        }));
    await c.askAgent('wy/s/downstream/agent', 'do it').drain<void>();
    expect(conn.sent.last['args'], VMap({'task': const VStr('do it')}));

    await c.answerTask(task, answers: {'q1': ['a'], 'q2': 'my words'}).drain<void>();
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
