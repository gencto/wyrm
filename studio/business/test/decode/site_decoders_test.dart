import 'dart:typed_data';

import 'package:business/wyrm/calls.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_val.dart';
import 'package:business/wyrm/decode/param_spec.dart';
import 'package:business/wyrm/decode/peers.dart';
import 'package:business/wyrm/decode/sys_answers.dart';
import 'package:business/wyrm/mappers/live_overlay_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/json_value.dart';
import 'package:models/link_revision.dart';
import 'package:models/live_value.dart';
import 'package:models/logging_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

NodeMeta _wire(NodeMeta meta) {
  final w = CborWriter();
  meta.encode(w);
  return NodeMeta.decode(CborReader(w.takeBytes()));
}

Child _broker(String name, [Map<String, Value> attr = const {}]) => Child(
  name,
  _wire(NodeMeta(is_: const TText('wy:broker'), attr: attr)),
);

Invalid<T> _invalid<T>(Decoded<T> d) {
  expect(d, isA<Invalid<T>>());
  return d as Invalid<T>;
}

T _valid<T>(Decoded<T> d) {
  expect(d, isA<Valid<T>>());
  return (d as Valid<T>).value;
}

/// The decoders behind Sites, the quarantine and the small answers of
/// `sys` (studio-rules §8): typed once, a value of another shape named
/// with its field, a kind this client does not know never shown as one it
/// knows.
void main() {
  group('a broker below', () {
    test('its site and the sites it relays', () {
      final p = _valid(
        downstreamPeerOf(
          'edge',
          _broker('plant-node', {
            'root': const VStr('wy/plant'),
            'site': const VStr('plant'),
            'via': const VArray([VStr('line1'), VStr('line2')]),
          }),
        )!,
      );
      expect(
        p,
        Peer(
          site: 'plant',
          kind: PeerKind.downstream,
          parent: 'edge',
          connected: true,
          via: const ['line1', 'line2'].lock,
        ),
      );
      // no `site`: the node's name
      expect(_valid(brokerSiteOf(_broker('line1'))!), 'line1');
      expect(_valid(downstreamPeerOf('edge', _broker('line1'))!).site, 'line1');
    });

    test('a child that is no broker is not one', () {
      final link = Child(
        'modbus',
        _wire(NodeMeta(is_: const TText('wy:link'))),
      );
      expect(downstreamPeerOf('edge', link), isNull);
      expect(brokerSiteOf(link), isNull);
      expect(brokerSiteOf(Child('x', NodeMeta())), isNull);
    });

    test('attributes of another shape are refused with their name', () {
      final site = _broker('plant', {'site': const VInt(7)});
      expect(
        brokerSiteOf(site),
        const Invalid<String>('downstream broker', 'site', 'not a text'),
      );
      expect(_invalid(downstreamPeerOf('edge', site)!).field, 'site');
      final via = _broker('plant', {
        'via': const VArray([VInt(1)]),
      });
      final i = _invalid(downstreamPeerOf('edge', via)!);
      expect((i.field, i.reason), ('via', 'not texts'));
    });
  });

  group('an upstream', () {
    const values = <String, Value>{
      'url': VStr('quic://central.example:7447'),
      'status': VStr('issued'),
      'enabled': VBool(true),
      'allow_config': VBool(false),
    };

    test('its values, typed; connected only when enabled', () {
      expect(
        upstreamPeerOf(
          'plant',
          'central',
          NodeMeta(),
          values,
          anyConnected: true,
        ),
        const Valid(
          Peer(
            site: 'central',
            kind: PeerKind.upstream,
            parent: 'plant',
            connected: true,
            url: 'quic://central.example:7447',
            status: 'issued',
            allowConfig: false,
          ),
        ),
      );
      expect(
        _valid(
          upstreamPeerOf(
            'plant',
            'central',
            NodeMeta(),
            {...values, 'enabled': const VBool(false)},
            anyConnected: true,
          ),
        ).connected,
        isFalse,
      );
      expect(
        _valid(
          upstreamPeerOf(
            'plant',
            'central',
            NodeMeta(),
            values,
            anyConnected: false,
          ),
        ).connected,
        isFalse,
      );
      // a leaf with no value yet is read from the attribute of its name
      expect(
        _valid(
          upstreamPeerOf(
            'plant',
            'central',
            _wire(NodeMeta(attr: {'url': const VStr('quic://a:1')})),
            const {},
            anyConnected: true,
          ),
        ).url,
        'quic://a:1',
      );
    });

    test('a leaf of another type is refused with its name', () {
      for (final (leaf, value, reason) in <(String, Value, String)>[
        ('url', const VInt(7447), 'not a text'),
        ('status', const VBool(true), 'not a text'),
        // "yes" is not taken as enabled
        ('enabled', const VStr('yes'), 'not a bool'),
        ('allow_config', const VInt(1), 'not a bool'),
        ('val_hz', const VStr('fast'), 'not a number'),
      ]) {
        final i = _invalid(
          upstreamPeerOf(
            'plant',
            'central',
            NodeMeta(),
            {...values, leaf: value},
            anyConnected: true,
          ),
        );
        expect((i.shape, i.field, i.reason), ('upstream', leaf, reason));
      }
    });

    test('the count of upstream connections', () {
      expect(upstreamConnectedOf(const VInt(1)), const Valid(true));
      expect(upstreamConnectedOf(const VInt(0)), const Valid(false));
      expect(upstreamConnectedOf(const VFloat(2)), const Valid(true));
      expect(upstreamConnectedOf(null), const Valid(false));
      expect(
        upstreamConnectedOf(const VStr('1')),
        const Invalid<bool>('sys', 'upstream_connected', 'not a number'),
      );
    });
  });

  group('what waits in quarantine', () {
    NodeMeta entry(Map<String, Value> attr) =>
        _wire(NodeMeta(display: 'broker:plant', attr: attr));

    test('a broker that waits, its relays and key', () {
      expect(
        quarantineEntryOf(
          'broker_plant',
          entry({
            'kind': const VStr('broker'),
            'first_seen': const VInt(1794108760),
            'key': const VStr('ab12'),
            'via': const VStr('site_a, site_b'),
            'held': const VBool(true),
          }),
        ),
        Valid(
          QuarantineEntry(
            cn: 'broker:plant',
            node: 'broker_plant',
            kind: QuarantineKind.broker,
            firstSeen: DateTime.utc(2026, 11, 8, 3, 32, 40),
            via: const ['site_a', 'site_b'].lock,
            key: 'ab12',
            deauthorized: true,
          ),
        ),
      );
      expect(
        _valid(
          quarantineEntryOf('x', entry({'kind': const VStr('link')})),
        ).kind,
        QuarantineKind.link,
      );
    });

    test('a kind that is missing or unknown is never shown as a link', () {
      final none = _invalid(quarantineEntryOf('x', entry(const {})));
      expect(
        (none.shape, none.field, none.reason),
        (
          'quarantine entry',
          'kind',
          'missing',
        ),
      );
      final other = _invalid(
        quarantineEntryOf('x', entry({'kind': const VStr('gateway')})),
      );
      expect((other.field, other.reason), ('kind', 'not a known name'));
    });

    test('attributes of another shape are refused with their name', () {
      for (final (attr, value, reason) in <(String, Value, String)>[
        ('first_seen', const VStr('yesterday'), 'not an ISO 8601 time'),
        ('first_seen', const VBool(true), 'not a time'),
        ('first_seen', const VInt(0), 'not a time'),
        ('key', const VInt(1), 'not a text'),
        ('held', const VStr('yes'), 'not a bool'),
        ('via', const VInt(3), 'not an array'),
        ('from', const VInt(3), 'not a text'),
      ]) {
        final i = _invalid(
          quarantineEntryOf(
            'x',
            entry({'kind': const VStr('link'), attr: value}),
          ),
        );
        expect((i.field, i.reason), (attr, reason), reason: '$attr $value');
      }
    });
  });

  group('small answers of sys', () {
    test('tokens: one row {token} each', () {
      expect(
        _valid(
          issuedTokensOf(const [
            VMap({'token': VStr('abc.def')}),
            VMap({'token': VStr('ghi.jkl')}),
          ]),
        ),
        ['abc.def', 'ghi.jkl'],
      );
      // a token is shown once: nothing else is shown in its place
      for (final (rows, field, reason) in <(List<Value>, String, String)>[
        (const [VStr('abc.def')], '', 'not a map'),
        (const [VMap({})], 'token', 'missing'),
        (
          const [
            VMap({'token': VInt(7)}),
          ],
          'token',
          'not a text',
        ),
      ]) {
        final i = _invalid(issuedTokensOf(rows));
        expect((i.field, i.reason), (field, reason));
      }
    });

    test('link revisions: newest first, the parameters as text', () {
      final revs = _valid(
        linkRevisionsOf(const [
          VArray([
            VMap({
              'rev': VInt(1),
              'params': VMap({'host': VStr('10.0.0.1')}),
            }),
            VMap({'rev': VInt(3), 'params': VMap({})}),
          ]),
          VMap({'rev': VInt(2)}),
        ]),
      );
      expect([for (final r in revs) r.rev], [3, 2, 1]);
      expect(revs.last.params, contains('"host": "10.0.0.1"'));
      expect(revs, everyElement(isA<LinkRevision>()));
      for (final (rows, field, reason) in <(List<Value>, String, String)>[
        (const [VStr('rev 1')], '', 'not a map'),
        // a revision without its number is not revision 0
        (
          const [
            VMap({'params': VMap({})}),
          ],
          'rev',
          'missing',
        ),
        (
          const [
            VMap({'rev': VStr('1')}),
          ],
          'rev',
          'not a whole number',
        ),
      ]) {
        final i = _invalid(linkRevisionsOf(rows));
        expect((i.field, i.reason), (field, reason));
      }
    });

    test('a watch group and the statistics of the historian', () {
      final watches = [
        Child('w1', _wire(NodeMeta(display: 'wy/plant/downstream/modbus/t1'))),
        // a leaf is a value of the group, not a watch
        Child('interval', _wire(NodeMeta(ty: TypeCode.number))),
      ];
      expect(
        watchGroupOf('fast', const {
          'logging_type': VStr('Interval'),
          'interval': VInt(5),
          'buffer_flush_time': VFloat(2.5),
        }, watches),
        Valid(
          WatchGroup(
            name: 'fast',
            loggingType: LoggingType.interval,
            interval: 5,
            flush: 2.5,
            watchIds: const ['w1'].lock,
            keys: const ['wy/plant/downstream/modbus/t1'].lock,
          ),
        ),
      );
      final i = _invalid(
        watchGroupOf('fast', const {'interval': VStr('5 s')}, const []),
      );
      expect(
        (i.shape, i.field, i.reason),
        (
          'watch group',
          'interval',
          'not a number',
        ),
      );
      expect(
        _invalid(
          watchGroupOf('fast', const {'logging_type': VInt(1)}, const []),
        ).field,
        'logging_type',
      );

      expect(historianStatOf('rows', const VInt(12)), const Valid('12'));
      expect(historianStatOf('free', const VFloat(3)), const Valid('3'));
      expect(historianStatOf('ratio', const VFloat(0.5)), const Valid('0.5'));
      expect(
        historianStatOf('auto_purge', const VBool(true)),
        const Valid('true'),
      );
      expect(
        historianStatOf('path', const VStr('/data')),
        const Valid('/data'),
      );
      expect(
        historianStatOf('sinks', const VMap({})),
        const Invalid<String>(
          'historian',
          'sinks',
          'not a text, a number or a bool',
        ),
      );
    });

    test("a flow's value read from the wire", () {
      expect(
        flowValOfWire(
          const VMap({
            'state': VInt(2),
            'error': VStr('no rights'),
            'version': VInt(4),
            'deployed_by': VStr('user:olena'),
          }),
        ),
        const Valid(
          FlowVal(
            state: 2,
            error: 'no rights',
            version: 4,
            deployedBy: 'user:olena',
          ),
        ),
      );
      expect(flowValOfWire(null), const Valid(FlowVal()));
      expect(
        flowValOfWire(const VStr('running')),
        const Invalid<FlowVal>('flow value', '', 'not a map'),
      );
    });
  });

  group('how a watch group records (wyrm-history `Logging`)', () {
    test("the names are the broker's", () {
      expect(
        [for (final l in LoggingType.values) l.wire],
        ['None', 'Interval', 'All Data', 'Point Change'],
      );
      expect(LoggingType.fromWire('interval'), isNull);
    });

    test('a name Studio does not know refuses the group', () {
      final i = _invalid(
        watchGroupOf('fast', const {
          'logging_type': VStr('Deadband'),
        }, const []),
      );
      expect((i.field, i.reason), ('logging_type', 'not a known name'));
      // no value yet is not a way of recording
      expect(
        _valid(watchGroupOf('fast', const {}, const [])).loggingType,
        isNull,
      );
    });

    test('a live value of another shape keeps what the group holds', () {
      const g = WatchGroup(
        name: 'fast',
        loggingType: LoggingType.interval,
        interval: 5,
      );
      IList<WatchGroup> live(Map<String, Object?> values) => liveGroups(
        [g].lock,
        'wy/p/sys/history',
        {
          for (final e in values.entries)
            'wy/p/sys/history/fast/${e.key}': LiveValue(
              value: e.value,
              time: DateTime.utc(2026),
            ),
        }.lock,
      );
      expect(
        live({'logging_type': 'All Data', 'interval': 2.5}).single,
        g.copyWith(loggingType: LoggingType.allData, interval: 2.5),
      );
      expect(live({'logging_type': 'Deadband', 'interval': '5 s'}).single, g);
      expect(live(const {}).single, g);
    });
  });

  group("a parameter's default (spec 02)", () {
    test('is the JSON it is, typed once', () {
      expect(
        paramDefaultOf(const VStr('pump')),
        const Valid<JsonValue?>(JsonText('pump')),
      );
      expect(
        paramDefaultOf(const VInt(5)),
        const Valid<JsonValue?>(JsonNumber(5)),
      );
      expect(paramDefaultOf(null), const Valid<JsonValue?>(null));
      expect(paramDefaultOf(const VNull()), const Valid<JsonValue?>(null));
      expect(
        paramSpecOf('name', ParamMeta(defaultValue: const VStr('x'))),
        paramSpecOf('name', ParamMeta(defaultValue: const VStr('x'))),
      );
    });

    test('a default JSON has no form for is refused', () {
      expect(
        paramDefaultOf(VBytes(Uint8List.fromList([1, 2]))),
        const Invalid<JsonValue?>('parameter', 'default', 'not JSON'),
      );
    });

    test('a prefilled display is one whose default is a text', () {
      ParamSpec display(JsonValue? d) =>
          ParamSpec(name: 'display', defaultValue: d);
      expect(clearedNames([display(const JsonText('Pump 1'))]), {'display'});
      expect(clearedNames([display(const JsonText('  '))]), isEmpty);
      // a number is not a prefilled name
      expect(clearedNames([display(const JsonNumber(7))]), isEmpty);
      expect(clearedNames([display(null)]), isEmpty);
      expect(
        clearedNames([
          const ParamSpec(name: 'unit', defaultValue: JsonText('bar')),
        ]),
        isEmpty,
      );
    });
  });
}
