// The FFI path end to end: dart:ffi → crates/wyrm-ffi → wyrm-client →
// in-process Zenoh + mock link (cargo feature `test-harness`).
//
// The test builds the library with cargo unless WYRM_FFI_LIB names a
// library that was built with `--features test-harness`.
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_ffi/wyrm_ffi.dart';

const root = 'wy/test/down/mock';
final repo = Directory.current.parent.parent.path;

Future<String> _library() async {
  final env = Platform.environment['WYRM_FFI_LIB'];
  if (env != null) return env;
  final r = await Process.run('cargo', ['build', '-p', 'wyrm-ffi', '--features', 'test-harness'],
      workingDirectory: repo);
  if (r.exitCode != 0) throw StateError('cargo build failed:\n${r.stderr}');
  final target = Platform.environment['CARGO_TARGET_DIR'] ?? '$repo/target';
  final name = Platform.isMacOS ? 'libwyrm_ffi.dylib' : Platform.isWindows ? 'wyrm_ffi.dll' : 'libwyrm_ffi.so';
  return '$target/debug/$name';
}

void main() {
  late String lib;
  late FrameClient c;

  setUpAll(() async {
    lib = await _library();
    c = await WyrmFfi.openTestMock(library: lib);
  });

  tearDownAll(() => c.close());

  test('children and meta', () async {
    final kids = await c.children(root);
    expect(kids.map((k) => k.name), ['g0', 'g1']);
    final m = await c.meta('$root/g0/p0');
    expect(m.ty, TypeCode.number);
    expect(m.unit, const TText('°C'));
  });

  test('list: refreshed first; cancel unsubscribes', () async {
    final first = await c.list(root).first.timeout(const Duration(seconds: 10));
    expect((first as ListRefreshed).children.map((k) => k.name), ['g0', 'g1']);
    final again = await c.list('$root/g1').first.timeout(const Duration(seconds: 10));
    expect((again as ListRefreshed).children.map((k) => k.name), containsAll(['p1', 'p3', 'p5']));
  });

  test('subscribe a pattern', () async {
    final keys = <String>{};
    await for (final ev in c.subscribe('$root/**').timeout(const Duration(seconds: 10))) {
      if (ev is ValSample) keys.add(ev.key);
      if (keys.length >= 6) break;
    }
    expect(keys, hasLength(6));
  });

  test('set, then the value comes back', () async {
    await c.set('$root/g0/p2', const VFloat(-3.25));
    final s = await c
        .subscribe('$root/g0/p2')
        .where((e) => e is ValSample && e.sample.v == const VFloat(-3.25))
        .first
        .timeout(const Duration(seconds: 10));
    expect(s.key, '$root/g0/p2');
  });

  test('history: the native call answers; nobody records the mock', () async {
    expect(await c.history('$root/g0/p0', from: '2020-01-01'), isEmpty);
  });

  test('invoke a stream action', () async {
    final out = await c.invoke(root, 'count', VMap({'n': const VInt(4)})).toList();
    expect(out, [const VInt(0), const VInt(1), const VInt(2), const VInt(3)]);
  });

  test('errors carry a status', () async {
    await expectLater(c.set('$root/g0/p2', const VStr('x')), throwsA(isA<WyrmException>()));
    await expectLater(c.invoke(root, 'nope').toList(), throwsA(isA<WyrmException>()));
  });

  test('open on a bad endpoint fails with a message', () async {
    await expectLater(
      WyrmFfi.open('bogus', library: lib),
      throwsA(isA<WyrmException>().having((e) => e.message, 'message', isNotEmpty)),
    );
  });

  test('close ends open streams', () async {
    final c2 = await WyrmFfi.openTestMock(library: lib);
    final done = c2.subscribe('$root/**').drain<void>().catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await c2.close();
    await done.timeout(const Duration(seconds: 10));
    expect(c2.isClosed, isTrue);
  });
}
