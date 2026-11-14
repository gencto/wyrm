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

  test('suggestions, replaced and review are read from a record', () async {
    final record = VMap({
      'state': const VStr('failed'),
      'replaced_by': const VStr('t2-2'),
      'review': const VStr('the device does not answer'),
      'reviewing': const VBool(true),
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
        const VStr('not a suggestion'),
      ]),
    });
    final s = TaskSuggestion.of(record);
    expect(s.length, 2);
    expect((s[0].id, s[0].changes, s[0].step), ('s1', 1, 2));
    expect(s[0].rows, isEmpty);
    expect(s[0].ask(), 'Try slave id 4. 3 is used by ahu-old');
    expect((s[1].step, s[1].rows.length, s[1].rows[0].key), (null, 2, 'wy/s/downstream/m/u4'));
    expect(s[1].ask([s[1].rows[1]]), 'Same for more units\nFor: unit 5');
    expect(replacedBy(record), 't2-2');
    expect(reviewOf(record), 'the device does not answer');
    expect(isReviewing(record), isTrue);
    // the public value: a count, the task id, no text
    final value = VMap({'state': const VStr('failed'), 'suggestions': const VInt(2), 'replaced_by': const VStr('t2-2')});
    expect((suggestionCount(value), replacedBy(value), isReviewing(value)), (2, 't2-2', false));
    // a record of an agent link older than the fields
    final old = VMap({'state': const VStr('done'), 'plan': VArray(const [])});
    expect(TaskSuggestion.of(old), isEmpty);
    expect((replacedBy(old), reviewOf(old), isReviewing(old), suggestionCount(old)), (null, null, false, 0));
    expect(TaskSuggestion.of(null), isEmpty);

    // picking one is a follow-up ask: its text, the parent, the ticked rows as context
    final conn = _Conn();
    final c = FrameClient(conn);
    await c.askSuggestion('wy/s/downstream/agent', 't1-1', s[1], rows: [s[1].rows[0]]).drain<void>();
    expect(
        conn.sent.last['args'],
        VMap({
          'task': const VStr('Same for more units\nFor: unit 4'),
          'parent': const VStr('t1-1'),
          'context': VArray([const VStr('wy/s/downstream/m/u4')]),
        }));
    await c.askSuggestion('wy/s/downstream/agent', 't1-1', s[0]).drain<void>();
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
