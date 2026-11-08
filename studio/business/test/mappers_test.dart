import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:business/wyrm/mappers/link_info_mapper.dart';
import 'package:business/wyrm/mappers/live_value_mapper.dart';
import 'package:business/wyrm/mappers/node_info_mapper.dart';
import 'package:business/wyrm/mappers/package_info_mapper.dart';
import 'package:business/wyrm/mappers/param_spec_mapper.dart';
import 'package:business/wyrm/mappers/peer_mapper.dart';
import 'package:business/wyrm/mappers/quarantine_entry_mapper.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/link_mode.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quality.dart' as m;
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// Every meta goes through CBOR once, as it arrives from a gateway.
NodeMeta wire(NodeMeta meta) {
  final w = CborWriter();
  meta.encode(w);
  return NodeMeta.decode(CborReader(w.takeBytes()));
}

// The shapes below are what the demo brokers answer (examples/demo/run.sh,
// 2026-11-08): edge `sys/links/modbus`, `downstream/*`, `sys/links` actions.
void main() {
  group('nodeInfoOf', () {
    test('a link node of downstream: a triangle, actions, a profile', () {
      final n = nodeInfoOf(
        'wy/edge/downstream',
        Child(
          'modbus',
          wire(
            NodeMeta(
              is_: const TText('wy:link'),
              hasNodes: true,
              attr: {'driver': const VStr('modbus')},
              actions: {'add_ip_connection': ActionMeta()},
            ),
          ),
        ),
      );

      expect(n.key, 'wy/edge/downstream/modbus');
      expect(n.name, 'modbus');
      expect(n.hasChildren, isTrue);
      expect(n.isAction, isTrue);
      expect(n.profile, 'wy:link');
      expect(n.type, isNull);
    });

    test('a writable value: its type, unit, level and choices', () {
      final n = nodeInfoOf(
        'wy/central/sys',
        Child(
          'log_level',
          wire(
            NodeMeta(
              ty: TypeCode.enum_,
              writable: Writable.config,
              enumValues: ['info', 'debug'],
              unit: const TText('°C'),
              hasHistory: true,
            ),
          ),
        ),
      );

      expect(n.type, 'enum');
      expect(n.writable, 'config');
      expect(n.choices, ['info', 'debug']);
      expect(n.unit, '°C');
      expect(n.hasChildren, isFalse, reason: 'no has_nodes: no triangle');
      expect(n.hasHistory, isTrue);
    });
  });

  group('linkInfoOf', () {
    test('reads driver and mode from attr, state from its code', () {
      final l = linkInfoOf(
        'modbus',
        wire(
          NodeMeta(
            is_: const TText('wy:link-def'),
            attr: {
              'rev': const VInt(1),
              'mode': const VStr('process'),
              'driver': const VStr('modbus'),
              'origin': const VStr('config'),
            },
          ),
        ),
        state: linkStateOf(2),
      );

      expect(l.id, 'modbus');
      expect(l.driver, 'modbus');
      expect(l.mode, LinkMode.process);
      expect(l.state, 'connected');
    });

    test('state codes follow wyrm-admin STATES', () {
      expect(
        [for (var i = 0; i < 6; i++) linkStateOf(i)],
        [
          'installed',
          'starting',
          'connected',
          'stopping',
          'stopped',
          'failed',
        ],
      );
      expect(linkStateOf(99), 'installed');
      expect(linkStateOf('failed'), 'failed');
    });
  });

  test('quarantineEntryOf: a broker that waits, its relays and key', () {
    final q = quarantineEntryOf(
      'broker_plant',
      wire(
        NodeMeta(
          is_: const TText('wy:quarantine'),
          display: 'broker:plant',
          attr: {
            'kind': const VStr('broker'),
            'first_seen': const VInt(1794108760),
            'key': const VStr('ab12'),
            'via': const VStr('site_a, site_b'),
          },
        ),
      ),
    );

    expect(q.cn, 'broker:plant');
    expect(q.node, 'broker_plant');
    expect(q.kind, 'broker');
    expect(q.via, ['site_a', 'site_b']);
    expect(q.key, 'ab12');
    expect(q.firstSeen, DateTime.utc(2026, 11, 8, 3, 32, 40));
  });

  test('packageInfoOf', () {
    final p = packageInfoOf(
      'postgres-process',
      wire(
        NodeMeta(
          attr: {
            'version': const VStr('0.1.0'),
            'kind': const VStr('process'),
            'source': const VStr('repository'),
            'sha256': const VStr('ff'),
          },
        ),
      ),
    );

    expect(p.version, '0.1.0');
    expect(p.kind, 'process');
    expect(p.source, 'repository');
  });

  test('downstreamPeerOf: only brokers', () {
    final broker = Child(
      'plant',
      wire(
        NodeMeta(
          is_: const TText('wy:broker'),
          attr: {
            'root': const VStr('wy/plant'),
            'site': const VStr('plant'),
          },
        ),
      ),
    );
    final link = Child('modbus', wire(NodeMeta(is_: const TText('wy:link'))));

    final p = downstreamPeerOf('edge', broker)!;
    expect(p.site, 'plant');
    expect(p.kind, PeerKind.downstream);
    expect(p.parent, 'edge');
    expect(downstreamPeerOf('edge', link), isNull);
  });

  test('paramSpecsOf: install_repo of sys/links', () {
    final a = ActionMeta()
      ..params['name'] = ParamMeta(ty: TypeCode.string, required: true)
      ..params['package'] = ParamMeta(
        ty: TypeCode.string,
        required: true,
        enumValues: ['modbus', 'mqtt'],
      )
      ..params['zip'] = ParamMeta(ty: TypeCode.binary, editor: 'file')
      ..params['token'] = ParamMeta(
        ty: TypeCode.string,
        editor: 'password',
        placeholder: 'one-time',
      );

    final specs = paramSpecsOf(a);

    expect(
      [for (final s in specs) s.name],
      ['name', 'package', 'zip', 'token'],
    );
    expect(specs[0].required, isTrue);
    expect(specs[1].type, 'enum');
    expect(specs[1].choices, ['modbus', 'mqtt']);
    expect(specs[2].editor, 'file');
    expect(specs[3].secret, isTrue);
    expect(specs[3].editor, isNull);
    expect(specs[3].description, 'one-time');
  });

  test('liveValueOf', () {
    final v = liveValueOf(
      const Sample(VFloat(21.5), q: Quality.uncertain, t: 1794108760204785),
    );

    expect(v.value, 21.5);
    expect(v.quality, m.Quality.uncertain);
    expect(v.time.microsecondsSinceEpoch, 1794108760204785);
  });

  test('agentTaskOf: a plan waiting for approval', () {
    final t = agentTaskOf(
      't1',
      Value.from({
        'state': 'awaiting_approval',
        'ask': 'add a modbus device',
        'owner': 'user:admin',
        'plan': [
          {
            'op': 'invoke',
            'key': 'wy/edge/downstream/modbus',
            'action': 'add_ip_connection',
            'args': {'host': '127.0.0.1', 'port': 502},
            'level': 'config',
            'approval': true,
            'reason': 'the device is new',
          },
        ],
        'log': ['read wy/edge/downstream'],
        'tokens': 1200,
      }),
    );

    expect(t.state, TaskState.awaitingApproval);
    expect(t.plan.single.action, 'add_ip_connection');
    expect(t.plan.single.args['port'], 502);
    expect(t.plan.single.approval, isTrue);
    expect(t.log.single, 'read wy/edge/downstream');
    expect(t.tokens, 1200);
  });

  group('values', () {
    test('time accepts seconds, milliseconds, microseconds and ISO text', () {
      final t = DateTime.utc(2026, 11, 8);
      final s = t.millisecondsSinceEpoch ~/ 1000;
      expect(time(VInt(s)), t);
      expect(time(VInt(s * 1000)), t);
      expect(time(VInt(s * 1000000)), t);
      expect(time(const VStr('2026-11-08T00:00:00Z')), t);
      expect(time(const VInt(0)), isNull);
    });

    test('toDart unwraps nested values', () {
      expect(
        toDart(
          Value.from({
            'a': [1, 2.5, true, null, 'x'],
          }),
        ),
        {
          'a': [1, 2.5, true, null, 'x'],
        },
      );
    });
  });
}
