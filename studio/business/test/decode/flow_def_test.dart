import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_edge.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A flow `~def` (spec 06) read once into a draft, and written back.
void main() {
  final def = <String, Object?>{
    'id': 'tank',
    'version': 3,
    'description': 'tank level',
    'nodes': {
      'level': {'type': 'subscribe', 'key': 'downstream/m/level'},
      'k': {'type': 'scale', 'k': 2},
      'mean1': {'type': 'block:mean'},
    },
    'edges': [
      ['level.out', 'k.in'],
      ['k.out', 'mean1.in.0'],
    ],
    'layout': {
      'level': [40, 60],
      'k~pin~p:k': [1, 0],
      'k~pin~out:out': [0, 0],
    },
  };

  FlowRead valid(Map<String, Object?> m) =>
      switch (flowReadOf('tank', Value.from(m))) {
        Valid(:final value) => value,
        final Invalid<FlowRead> i => fail('$i'),
      };

  Invalid<FlowRead> invalid(Object? m) =>
      switch (flowReadOf('tank', Value.from(m))) {
        final Invalid<FlowRead> i => i,
        Valid() => fail('$m read'),
      };

  test('a definition reads as blocks, typed edges, pins and the rest', () {
    final r = valid(def);
    final d = r.draft;
    expect(d.version, 3);
    expect(d.blocks['level']!.type.known, KnownBlock.subscribe);
    expect(d.blocks['mean1']!.type, const CustomType('mean'));
    expect(d.blocks['k']!.cfg.unlock, {'k': 2});
    expect(d.edges.first.source, PortEnd('level', 'out'));
    expect(d.edges.last.target, PortEnd('mean1', 'in.0'));
    expect(d.blocks['k']!.pins.unlock, {'p:k': true, 'out:out': false});
    expect(r.placed, {'level'}.lock, reason: 'only level has a place');
    expect(d.rest['description'], 'tank level');
    expect(d.rest.containsKey('nodes'), isFalse);
  });

  test('written back it reads the same: blocks, edges, places and pins', () {
    final d = valid(def).draft;
    final again = valid(defJsonOf(d, d.version)).draft;
    expect(again.blocks, d.blocks);
    expect(again.edges, d.edges);
    expect(again.rest, d.rest);
    expect(defOf(again, 3), defOf(d, 3));
    expect(
      pinKey('k', const FieldId.param('k')),
      'k~pin~p:k',
      reason: 'the key a pin travels under',
    );
  });

  test('a flow that writes gets maxperm write when it names none', () {
    final d = valid({
      'nodes': {
        's': {'type': 'set', 'path': 'downstream/m/sp'},
      },
    }).draft;
    expect(defJsonOf(d, 1)['permissions'], {'maxperm': 'write'});
    expect(previewDefOf(d.copyWith(id: '')), isA<VMap>());
  });

  test('the preview has no layout and no version: a move runs nothing', () {
    final d = valid(def).draft;
    final moved = d.copyWith(
      blocks: d.blocks.add('k', d.blocks['k']!.copyWith(x: 999)),
    );
    expect(previewDefOf(moved), previewDefOf(d));
    expect(defOf(moved, 1), isNot(defOf(d, 1)));
  });

  test('a broken definition is invalid, with the field', () {
    expect(invalid(['nodes']).field, '');
    expect(invalid({'nodes': <Object?>[]}).field, 'nodes');
    expect(
      invalid({
        'nodes': {'a': 1},
      }).field,
      'nodes.a',
    );
    expect(
      invalid({
        'nodes': {'a': <String, Object?>{}},
      }).field,
      'nodes.a.type',
    );
    expect(
      invalid({
        'edges': [
          ['a.out'],
        ],
      }).field,
      'edges[0]',
    );
    final noPort = invalid({
      'edges': [
        ['a', 'b.in'],
      ],
    });
    expect((noPort.field, noPort.reason), ('edges[0]', 'not <node>.<port>'));
    expect(invalid({'edges': 'a.out'}).field, 'edges');
    expect(invalid({'layout': <Object?>[]}).field, 'layout');
    expect(invalid({'version': 'three'}).field, 'version');
  });

  test('a place that is no pair of numbers stands on the grid; a pin of no '
      'field is not kept', () {
    final r = valid({
      'nodes': {
        'a': {'type': 'not'},
      },
      'layout': {
        'a': ['x', 1],
        'a~pin~form': [1, 0],
        'a~pin~zz': [1, 0],
      },
    });
    expect(r.placed, isEmpty);
    expect(r.draft.blocks['a']!.pins, isEmpty);
  });

  test('the newest definition of a history', () {
    expect(newestFlowOf('tank', const VNull()), const Valid<FlowRead?>(null));
    expect(
      newestFlowOf('tank', const VArray([])),
      const Valid<FlowRead?>(null),
    );
    final r = newestFlowOf(
      'tank',
      Value.from([
        {'version': 1},
        def,
      ]),
    );
    expect(switch (r) {
      Valid(:final value) => value?.draft.version,
      Invalid() => null,
    }, 3);
    expect(newestFlowOf('tank', const VStr('x')), isA<Invalid<FlowRead?>>());
    expect(
      newestFlowOf(
        'tank',
        Value.from([
          {'nodes': 1},
        ]),
      ),
      const Invalid<FlowRead?>('flow def', 'nodes', 'not a map'),
    );
  });

  test('a wire end is node.port, split at the first dot', () {
    expect(portEndOf('a.in.0'), PortEnd('a', 'in.0'));
    expect(portEndOf('a'), isNull);
    expect(portEndOf('.in'), isNull);
    expect(portEndOf('a.'), isNull);
    expect(portEndOf(null), isNull);
    expect(
      FlowEdge.between(PortEnd('a', 'out'), PortEnd('b', 'in')),
      const FlowEdge(from: 'a', fromPort: 'out', to: 'b', toPort: 'in'),
    );
  });

  test('call arguments carry the definition as it is', () {
    final d = defOf(valid(def).draft, 4);
    expect(defArgs(d)['def'], d);
    expect(defArgs(d, maxHz: 4)['max_hz'], const VInt(4));
  });
}
