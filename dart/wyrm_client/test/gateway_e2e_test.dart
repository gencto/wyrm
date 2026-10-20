// End to end against a real gateway: crates/wyrm-gateway/examples/gateway_dev.rs
// (isolated Zenoh session + mock link + gateway on 127.0.0.1).
//
// The test builds the example with cargo unless WYRM_GATEWAY_DEV names a
// built binary. Without cargo and without that variable it fails.
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

const root = 'wy/test/down/mock';
final repo = Directory.current.parent.parent.path;

Future<String?> _binary() async {
  final env = Platform.environment['WYRM_GATEWAY_DEV'];
  if (env != null) return env;
  final r = await Process.run('cargo', ['build', '-p', 'wyrm-gateway', '--example', 'gateway_dev'],
      workingDirectory: repo);
  if (r.exitCode != 0) {
    throw StateError('cargo build failed:\n${r.stderr}');
  }
  final target = Platform.environment['CARGO_TARGET_DIR'] ?? '$repo/target';
  return '$target/debug/examples/gateway_dev${Platform.isWindows ? '.exe' : ''}';
}

void main() {
  late Process server;
  late Uri base;
  late WyrmGateway gw;
  late FrameClient c;

  setUpAll(() async {
    final bin = await _binary();
    server = await Process.start(bin!, []);
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    final port = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('PORT='))
        .timeout(const Duration(seconds: 30));
    base = Uri.parse('http://127.0.0.1:${port.substring(5)}');
    gw = await WyrmGateway.login(base, user: 'admin', password: 'admin password');
    c = await gw.connect();
  });

  tearDownAll(() async {
    await c.close();
    gw.dispose();
    server.stdin.writeln('quit');
    await server.stdin.close();
    await server.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      server.kill();
      return -1;
    });
  });

  test('a bad password is refused', () async {
    await expectLater(
      WyrmGateway.login(base, user: 'admin', password: 'wrong password'),
      throwsA(isA<WyrmException>().having((e) => e.status.known, 'status', Status.permissionDenied)),
    );
  });

  test('me', () async {
    final me = await gw.me();
    expect(me['sub'], const VStr('admin'));
  });

  test('children', () async {
    final kids = await c.children(root);
    expect(kids.map((k) => k.name), containsAll(['g0', 'g1']));
    expect(kids.first.meta.isContainer, isTrue);
  });

  test('meta of a point', () async {
    final m = await c.meta('$root/g0/p0');
    expect(m.ty, TypeCode.number);
    expect(m.unit, const TText('°C'));
    expect(m.isWritable, isTrue);
  });

  test('list: refreshed first, then cancel', () async {
    final first = await c.list(root).first.timeout(const Duration(seconds: 10));
    expect(first, isA<ListRefreshed>());
    expect((first as ListRefreshed).children.map((k) => k.name), ['g0', 'g1']);
    // The connection still works after the unsubscribe.
    final again = await c.list('$root/g0').first.timeout(const Duration(seconds: 10));
    expect((again as ListRefreshed).children.map((k) => k.name), containsAll(['p0', 'p2', 'p4']));
  });

  test('subscribe a pattern gets live samples', () async {
    final keys = <String>{};
    await for (final ev in c.subscribe('$root/**').timeout(const Duration(seconds: 10))) {
      if (ev is ValSample) {
        expect(ev.sample.q, Quality.good);
        expect(ev.sample.v.asDouble, isNotNull);
        keys.add(ev.key);
      }
      if (keys.length >= 6) break;
    }
    expect(keys, hasLength(6));
  });

  test('set, then the value comes back', () async {
    await c.set('$root/g1/p1', const VFloat(42.5));
    final s = await c
        .subscribe('$root/g1/p1')
        .where((e) => e is ValSample)
        .cast<ValSample>()
        .firstWhere((s) => s.sample.v == const VFloat(42.5))
        .timeout(const Duration(seconds: 10));
    expect(s.key, '$root/g1/p1');
    await c.invoke(root, 'reset').toList();
  });

  test('set out of type is refused', () async {
    await expectLater(c.set('$root/g1/p1', const VStr('text')), throwsA(isA<WyrmException>()));
  });

  test('invoke a stream action', () async {
    final out = await c.invoke(root, 'count', VMap({'n': const VInt(3)})).toList();
    expect(out.map((v) => v.asDouble), [0, 1, 2]);
  });

  test('invoke an unknown action fails', () async {
    await expectLater(c.invoke(root, 'nope').toList(), throwsA(isA<WyrmException>()));
  });

  test('a key outside the site is refused', () async {
    await expectLater(
      c.meta('wy/other/down'),
      throwsA(isA<WyrmException>().having((e) => e.status.known, 'status', Status.invalidParameter)),
    );
  });
}
