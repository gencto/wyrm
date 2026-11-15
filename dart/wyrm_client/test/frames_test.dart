// The frame protocol: request frames as the gateway reads them, server
// frames decoded once, unknown events skipped, malformed events reported
// on the stream that owns them.

import 'dart:async';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

class _Conn implements FrameTransport {
  final _in = StreamController<Value>();
  final sent = <FrameRequest>[];

  @override
  Stream<Value> get incoming => _in.stream;

  @override
  void send(FrameRequest request) => sent.add(request);

  void push(int id, Map<String, Value> f) =>
      _in.add(VMap({'id': VInt(id), ...f}));

  void event(int id, String type, Map<String, Value> f) => push(id, {
    'event': VMap({'type': VStr(type), ...f}),
  });

  @override
  Future<void> close() => _in.close();
}

void main() {
  test('a request frame carries only what it has', () {
    expect(
      const FrameRequest(
        7,
        FrameOp.doc,
        'wy/s/x',
        suffix: DocSuffix.def,
      ).toValue(),
      VMap({
        'id': const VInt(7),
        'op': const VStr('doc'),
        'key': const VStr('wy/s/x'),
        'suffix': const VStr('~def'),
      }),
    );
    expect(
      const FrameRequest(8, FrameOp.unsubscribe, '', sub: 3).toValue(),
      VMap({
        'id': const VInt(8),
        'op': const VStr('unsubscribe'),
        'sub': const VInt(3),
      }),
    );
  });

  test('server frames decode once', () {
    expect(
      ServerFrame.fromValue(
        VMap({'id': const VInt(1), 'ok': const VBool(true)}),
      ),
      isA<FrameOk>(),
    );
    final f = ServerFrame.fromValue(
      VMap({
        'id': const VInt(2),
        'ok': const VBool(false),
        'error': VMap({
          'status': VInt(Status.busy.code),
          'message': const VStr('busy'),
        }),
      }),
    );
    expect(
      f,
      isA<FrameFailed>().having(
        (f) => f.error.status.known,
        'status',
        Status.busy,
      ),
    );
    expect(
      ServerFrame.fromValue(
        VMap({
          'id': const VInt(3),
          'event': VMap({'type': const VStr('a_new_event')}),
        }),
      ),
      isA<FrameIgnored>(),
    );
    expect(
      () => ServerFrame.fromValue(VMap({'ok': const VBool(true)})),
      throwsA(
        isA<DecodeError>().having((e) => e.path, 'path', 'ServerFrame.id'),
      ),
    );
  });

  test('subscribe: a sample by name or code; a malformed one is an error on the stream', () async {
    final conn = _Conn();
    final c = FrameClient(conn);
    final got = <Object>[];
    final done = Completer<void>();
    final sub = c
        .subscribe('wy/s/downstream/m/**')
        .listen(got.add, onError: got.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);
    final id = conn.sent.single.id;
    expect(conn.sent.single.op, FrameOp.subscribe);
    conn
      ..push(id, {'ok': const VBool(true)})
      ..event(id, 'sample', {
        'key': const VStr('wy/s/downstream/m/a'),
        'v': const VInt(1),
        'q': const VStr('uncertain'),
        't': const VInt(5),
        'qual': const VStr('uncertain/stale'),
      })
      ..event(id, 'sample', {
        'key': const VStr('wy/s/downstream/m/b'),
        'v': const VInt(2),
        'q': const VInt(2),
      })
      ..event(id, 'sample', {'v': const VInt(3)})
      ..event(id, 'a_new_event', {})
      ..event(id, 'removed', {'key': const VStr('wy/s/downstream/m/a')})
      ..event(id, 'closed', {});
    await done.future;
    await sub.cancel();
    expect(got, hasLength(4));
    final a = got[0] as ValSample;
    expect(
      (a.key, a.sample.q, a.sample.t, a.qual),
      ('wy/s/downstream/m/a', Quality.uncertain, 5, 'uncertain/stale'),
    );
    expect((got[1] as ValSample).sample.q, Quality.bad);
    expect(
      got[2],
      isA<WyrmException>()
          .having((e) => e.status.known, 'status', Status.invalidMessage)
          .having((e) => e.message, 'message', contains('key')),
    );
    expect(got[3], isA<ValRemoved>());
    await c.close();
  });

  test('doc refuses a suffix that is not a document before sending', () async {
    final conn = _Conn();
    final c = FrameClient(conn);
    await expectLater(
      c.doc('wy/s/x', '~val'),
      throwsA(
        isA<WyrmException>().having(
          (e) => e.status.known,
          'status',
          Status.invalidParameter,
        ),
      ),
    );
    expect(conn.sent, isEmpty);
    await c.close();
  });
}
