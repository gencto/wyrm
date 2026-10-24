// ReconnectingClient over in-memory connections that the test drops, as a
// broker rebuild drops the gateway's WebSockets.

import 'dart:async';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// One connection of a fake gateway: answers `list`, `subscribe`, `meta`
/// and `set`; `held` requests get no answer until the connection drops.
class FakeConn implements FrameTransport {
  final FakeServer server;
  final _in = StreamController<Value>();
  FakeConn(this.server);

  @override
  Stream<Value> get incoming => _in.stream;

  void _reply(int id, Map<String, Value> f) => scheduleMicrotask(() {
        if (!_in.isClosed) _in.add(VMap({'id': VInt(id), ...f}));
      });

  @override
  void send(Map<String, Value> frame) {
    final id = (frame['id'] as VInt).v;
    final op = (frame['op'] as VStr).v;
    final key = switch (frame['key']) { VStr(:final v) => v, _ => '' };
    server.ops.add('$op $key');
    if (server.held.contains(op)) return;
    switch (op) {
      case 'list':
        _reply(id, {'ok': const VBool(true)});
        _reply(id, {
          'event': VMap({
            'type': const VStr('refreshed'),
            'children': VArray([
              for (final n in server.children)
                VMap({'name': VStr(n), 'meta': VBytes(NodeMeta(hasChildren: true).toCbor())}),
            ]),
          }),
        });
      case 'subscribe':
        _reply(id, {'ok': const VBool(true)});
        _reply(id, {
          'event': VMap({
            'type': const VStr('sample'),
            'key': VStr(key),
            'v': VInt(server.value),
            'q': const VStr('good'),
            't': const VInt(1),
          }),
        });
      case 'meta':
        _reply(id, {'ok': const VBool(true), 'result': VBytes(NodeMeta().toCbor())});
      default:
        _reply(id, {'ok': const VBool(true)});
    }
  }

  void drop() => _in.close();

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

class FakeServer {
  final ops = <String>[];
  final held = <String>{};
  var children = ['a'];
  var value = 1;
  FakeConn? conn;
  int connects = 0;

  /// Errors to throw from the next connects, in order.
  final refuse = <Object>[];

  Future<FrameClient> connect() async {
    connects++;
    if (refuse.isNotEmpty) throw refuse.removeAt(0);
    final c = conn = FakeConn(this);
    return FrameClient(c);
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('a lost connection: streams open again, calls wait for it', () async {
    final s = FakeServer();
    final c = await ReconnectingClient.open(s.connect, maxDelay: const Duration(milliseconds: 20));
    final states = <bool>[];
    c.connection.listen(states.add);

    final lists = <List<String>>[];
    final errors = <Object>[];
    final sub = c.list('wy/x').listen((u) {
      if (u case ListRefreshed(:final children)) lists.add([for (final k in children) k.name]);
    }, onError: errors.add);
    final vals = <Value>[];
    c.subscribe('wy/x/p').listen((e) {
      if (e case ValSample(:final sample)) vals.add(sample.v);
    }, onError: errors.add);
    await settle();
    expect(lists, [
      ['a']
    ]);
    expect(vals, [const VInt(1)]);

    // the broker rebuilds: the socket closes, a meta in flight goes again
    s.held.add('meta');
    final meta = c.meta('wy/x/p');
    await settle();
    s
      ..held.clear()
      ..children = ['a', 'b']
      ..value = 2
      ..refuse.add(StateError('connection refused'));
    s.conn!.drop();
    await settle();
    await meta;
    await settle();
    expect(s.connects, 3, reason: 'one refused, then up again');
    expect(states, [false, true]);
    expect(lists, [
      ['a'],
      ['a', 'b']
    ]);
    expect(vals, [const VInt(1), const VInt(2)]);
    expect(errors, isEmpty);

    // a set cut by a lost connection fails: it may have run
    s.held.add('set');
    final set = c.set('wy/x/p', const VInt(3));
    await settle();
    s.held.clear();
    s.conn!.drop();
    await expectLater(
        set, throwsA(isA<WyrmException>().having((e) => e.message, 'message', contains('may have run'))));
    await settle();
    expect(c.isConnected, isTrue);

    // a cancelled stream is not opened again
    await sub.cancel();
    s.ops.clear();
    s.conn!.drop();
    await settle();
    expect(s.ops.where((o) => o.startsWith('list')), isEmpty);
    expect(s.ops, contains('subscribe wy/x/p'));
    await c.close();
  });

  test('an expired login ends the client', () async {
    final s = FakeServer();
    final c = await ReconnectingClient.open(s.connect, maxDelay: const Duration(milliseconds: 20));
    final errors = <Object>[];
    var done = false;
    c.list('wy/x').listen((_) {}, onError: errors.add, onDone: () => done = true);
    await settle();
    s.refuse.add(WyrmException.of(Status.permissionDenied, 'not authenticated'));
    s.conn!.drop();
    await settle();
    expect(done, isTrue);
    expect(errors.single, isA<WyrmException>().having((e) => e.message, 'message', 'not authenticated'));
    await expectLater(c.meta('wy/x'), throwsA(isA<WyrmException>()));
    await c.close();
  });
}
