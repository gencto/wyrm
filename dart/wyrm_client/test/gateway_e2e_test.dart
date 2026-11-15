// End to end against a real gateway: crates/wyrm-gateway/examples/gateway_dev.rs
// (isolated Zenoh session + mock link + gateway on 127.0.0.1).
//
// The test builds the example with cargo unless WYRM_GATEWAY_DEV names a
// built binary. Without cargo and without that variable it fails.
@Timeout(Duration(minutes: 20))
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

const root = 'wy/test/downstream/mock';
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

  test('identity', () async {
    final me = await gw.identity();
    expect(me.sub, 'admin');
    expect(me.site, 'test');
    expect(me.max, Perm.config);
    expect(me.grants, isNotEmpty);
  });

  test('info and users decode', () async {
    final info = await WyrmGateway.info(base);
    expect(info.site, 'test');
    expect(info.role, GatewayRole.active);
    expect(info.tls, isFalse);
    final users = await gw.users();
    expect(users.map((u) => u.name), contains('admin'));
    expect(await gw.devices(), isA<List<GatewayDevice>>());
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

  test('large arguments go over POST /api/invoke, not a frame', () async {
    // 100 KiB do not fit a 64 KiB frame: the gateway's HTTP route answers
    // (only actions with a file parameter may use it), and the socket stays
    // usable.
    final big = VMap({'blob': VBytes(Uint8List(100 * 1024))});
    await expectLater(
        c.invoke(root, 'reset', big).toList(),
        throwsA(isA<WyrmException>().having((e) => e.message, 'message', contains('takes no file'))));
    await c.invoke(root, 'reset').toList();
  });

  test('a refused upload of 4 MiB carries the refusal, not a broken pipe', () async {
    // The client writes the whole body before it reads the answer; the
    // gateway reads a refused body to its end so that its answer arrives.
    final big = VMap({'blob': VBytes(Uint8List(4 << 20))});
    await expectLater(
        c.invoke(root, 'reset', big).toList(),
        throwsA(isA<WyrmException>().having((e) => e.message, 'message', contains('takes no file'))));
    await c.invoke(root, 'reset').toList();
  });

  test('invoke an unknown action fails', () async {
    await expectLater(c.invoke(root, 'nope').toList(), throwsA(isA<WyrmException>()));
  });

  test('a key outside the site is refused', () async {
    await expectLater(
      c.meta('wy/other/downstream'),
      throwsA(isA<WyrmException>().having((e) => e.status.known, 'status', Status.invalidParameter)),
    );
  });

  // Last: the restart closes `c` too.
  // ADR 0049: the agent link behind the gateway, with a scripted model.
  group('agent tasks', () {
    const agent = 'wy/test/downstream/agent';

    Future<AgentTaskRecord> record(String task, bool Function(AgentTaskState state) until) async {
      for (var i = 0; i < 400; i++) {
        final r = await c.agentRecord(task);
        if (until(r.state)) return r;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      fail('the task never got there');
    }

    AgentReplyState last(List<AgentReply> rows) => rows.whereType<AgentReplyState>().last;

    test('doc: the record of a task, a closed set of suffixes', () async {
      final rows = await c.agentAsk(agent, 'set two points').toList();
      expect(rows.first, isA<AgentReplyState>());
      expect(last(rows).state, AgentTaskState.awaitingApproval);
      final task = '$agent/tasks/${last(rows).task}';
      final rec = await c.agentRecord(task);
      expect(rec.ask, 'set two points');
      expect(rec.plan, hasLength(4));
      expect(rec.plan[0].kind, AgentStepKind.set);
      expect(rec.plan[0].node, '$root/g0/p0');
      expect(rec.plan[0].value, const VFloat(42.5));
      expect(rec.plan[0].level, Perm.write);
      expect(rec.plan[2].kind, AgentStepKind.expect);
      expect(rec.plan[2].node, '$root/g0/p0');
      // the hash made here is the link's (and the gateway's)
      expect(rec.shownPlanHash, isNotNull);
      expect(rec.shownPlanHash, rec.planHash);
      await expectLater(
          c.doc(task, 'state'),
          throwsA(isA<WyrmException>()
              .having((e) => e.status.known, 'status', Status.invalidParameter)
              .having(isUnknownOp, 'unknown op', isFalse)));
      await expectLater(c.docOf('$root/g0/p0', DocSuffix.state),
          throwsA(isA<WyrmException>().having((e) => e.status.known, 'status', Status.notSupported)));
      await c.invoke(task, 'reject').toList();
    });

    test('approve: the ticked step runs, the others are skipped', () async {
      await c.invoke(root, 'reset').toList();
      final rows = await c.agentAsk(agent, 'set two points').toList();
      final task = '$agent/tasks/${last(rows).task}';
      final rec = await c.agentRecord(task);
      final hash = rec.shownPlanHash!;
      // another plan than the one that is stored
      await expectLater(
          c.agentApprove(task, steps: [1], plan: '00'),
          throwsA(isA<WyrmException>().having((e) => e.message, 'message', contains('read it again'))));
      // a step that sends nothing
      await expectLater(c.agentApprove(task, steps: [3], plan: hash), throwsA(isA<WyrmException>()));
      final r = await c.agentApprove(task, steps: [1], plan: hash);
      expect(r?.state, AgentTaskState.running);
      final done = await record(task, (s) => s != AgentTaskState.running);
      expect(done.state, AgentTaskState.done);
      expect([for (final s in done.plan) s.result?.status], [
        AgentStepStatus.ok,
        AgentStepStatus.skipped,
        AgentStepStatus.ok,
        AgentStepStatus.skipped,
      ]);
      expect(done.plan[3].result?.message, 'skipped: needs step 2');
      // the public value: where the run is, in fixed words
      final val = await c
          .subscribe(task)
          .where((e) => e is ValSample)
          .cast<ValSample>()
          .first
          .timeout(const Duration(seconds: 10));
      final pub = AgentTaskValue.fromValue(val.sample.v);
      expect(pub.of, 4);
      expect(pub.last?.result, AgentStepStatus.skipped);
      await c.invoke(root, 'reset').toList();
    });

    test('the model asks back; the answer resumes it', () async {
      final rows = await c.agentAsk(agent, 'ask me first, then set two points').toList();
      expect(last(rows).state, AgentTaskState.awaitingAnswer);
      expect(rows.whereType<AgentReplyEvent>().map((e) => e.kind), contains(AgentEventKind.question));
      final task = '$agent/tasks/${last(rows).task}';
      final rec = await c.agentRecord(task);
      final q = rec.questions.single;
      expect(q.id, 'q1');
      expect(q.options, hasLength(2));
      await expectLater(
          c.agentAnswer(task, answers: {'q1': const AgentAnswer.options(['nope'])}).toList(),
          throwsA(isA<WyrmException>()));
      final after = await c.agentAnswer(task, answers: {'q1': const AgentAnswer.options(['g0'])}).toList();
      expect(last(after).state, AgentTaskState.awaitingApproval);
      final planned = await c.agentRecord(task);
      expect(planned.plan, hasLength(4));
      expect(planned.questions.single.answer, const AgentAnswer.options(['g0']));
      await c.invoke(task, 'cancel').toList();
    });
  });

  test('a gateway restart: a new socket, the streams open again', () async {
    final rc = await gw.client();
    final states = <bool>[];
    rc.connection.listen(states.add);
    var refreshes = 0;
    final errors = <Object>[];
    final sub = rc.list(root).listen((u) {
      if (u is ListRefreshed) refreshes++;
    }, onError: errors.add);
    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 200 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(ok(), isTrue);
    }

    await until(() => refreshes == 1);
    server.stdin.writeln('restart');
    await until(() => refreshes == 2);
    expect(states, [false, true]);
    expect(errors, isEmpty);
    expect((await rc.meta('$root/g0/p0')).isWritable, isTrue);
    expect(c.isClosed, isTrue, reason: 'a plain FrameClient stays closed');
    await sub.cancel();
    await rc.close();
  });
}
