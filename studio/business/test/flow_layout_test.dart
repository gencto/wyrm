import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:business/wyrm/decode/node_type.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_layout.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/block_types.dart';

// The automatic layout (flow-editor.md §25) on a real flow: the one the
// agent deployed on the demo's `central` (62 blocks, 74 wires, no saved
// layout), with the catalog of its block types as that broker gives it.

Map<String, Object?> _json(String name) =>
    jsonDecode(File('test/support/flows/$name').readAsStringSync())
        as Map<String, Object?>;

final Map<String, Object?> large = _json('large_flow.json');

final Map<String, NodeType> types = {
  for (final t in jsonDecode(
    File(
      'test/support/flows/large_flow_types.json',
    ).readAsStringSync(),
  ) as List<Object?>)
    (t! as Map<String, Object?>)['type']! as String: nodeTypeOf(Value.from(t))
        .orWarn('test')!,
};

/// [def] with its nodes in another order (a map's order says nothing).
Map<String, Object?> shuffled(Map<String, Object?> def, int seed) {
  final nodes = (def['nodes']! as Map<String, Object?>).entries.toList()
    ..shuffle(math.Random(seed));
  final edges = List.of(def['edges']! as List<Object?>)
    ..shuffle(math.Random(seed + 1));
  return {...def, 'nodes': Map.fromEntries(nodes), 'edges': edges};
}

Set<String> placedIdsOf(Value def) => readFlow('large', def).placed.unlock;

FlowDraft placed(Map<String, Object?> def) {
  final read = readFlow('large', Value.from(def));
  return placeFlow(read.draft, byType(types), placed: read.placed.unlock);
}

Map<String, (double, double)> at(FlowDraft d) => {
  for (final b in d.blocks.values) b.id: (b.x, b.y),
};

/// The layout the editor had before (columns by depth, each block under
/// the one before it): the yardstick the new one must beat.
FlowDraft oldColumns(FlowDraft d) {
  final depth = <String, int>{for (final id in d.blocks.keys) id: 0};
  for (var round = 0; round < d.blocks.length; round++) {
    var changed = false;
    for (final e in d.edges) {
      final next = (depth[e.from] ?? 0) + 1;
      if (depth.containsKey(e.to) &&
          next > depth[e.to]! &&
          next < d.blocks.length) {
        depth[e.to] = next;
        changed = true;
      }
    }
    if (!changed) {
      break;
    }
  }
  final y = <int, double>{};
  final blocks = <String, FlowBlock>{};
  for (final b in d.blocks.values) {
    final col = depth[b.id] ?? 0;
    final top = y[col] ?? 40;
    blocks[b.id] = b.copyWith(x: 40 + 300.0 * col, y: top);
    y[col] = top + blockHeight(types[b.type.wire], b, edges: d.edges) + 28;
  }
  return d.copyWith(blocks: blocks.lock);
}

({double left, double top, double right, double bottom}) bounds(
  FlowDraft d,
) {
  final bs = d.blocks.values;
  return (
    left: bs.map((b) => b.x).reduce(math.min),
    top: bs.map((b) => b.y).reduce(math.min),
    right: bs.map((b) => b.x + blockWidthOf(roleOf(b.type))).reduce(math.max),
    bottom: bs
        .map((b) => b.y + blockHeight(types[b.type.wire], b, edges: d.edges))
        .reduce(math.max),
  );
}

bool overlaps(FlowDraft d, [Map<BlockType, NodeType>? with_]) {
  final ts = with_ ?? byType(types);
  final rs = [
    for (final b in d.blocks.values)
      (
        b.x,
        b.y,
        b.x + blockWidthOf(roleOf(b.type)),
        b.y + blockHeight(ts[b.type], b, edges: d.edges),
      ),
  ];
  for (var i = 0; i < rs.length; i++) {
    for (var j = i + 1; j < rs.length; j++) {
      final a = rs[i];
      final c = rs[j];
      if (a.$1 < c.$3 && c.$1 < a.$3 && a.$2 < c.$4 && c.$2 < a.$4) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  group('a flow without a saved layout', () {
    final d = placed(large);
    final old = oldColumns(flowDraftOf('large', Value.from(large)));

    test('the fixture is the real flow', () {
      expect(d.blocks, hasLength(62));
      expect(d.edges, hasLength(74));
      expect(placedIdsOf(Value.from(large)), isEmpty);
    });

    test('is the same layout for the same definition, in any order', () {
      expect(at(placed(large)), at(d));
      for (final seed in [1, 2, 3]) {
        expect(at(placed(shuffled(large, seed))), at(d), reason: 'seed $seed');
      }
    });

    test('puts every block on the grid, none over another', () {
      for (final b in d.blocks.values) {
        expect(b.x % layoutGrid, 0, reason: b.id);
        expect(b.y % layoutGrid, 0, reason: b.id);
        expect(b.x, greaterThanOrEqualTo(layoutOrigin));
        expect(b.y, greaterThanOrEqualTo(layoutOrigin));
      }
      expect(overlaps(d), isFalse);
    });

    test('reads left to right: a wire never goes back', () {
      for (final e in d.edges) {
        final a = d.blocks[e.from]!;
        final b = d.blocks[e.to]!;
        expect(
          a.x + blockWidthOf(roleOf(a.type)),
          lessThanOrEqualTo(b.x),
          reason: '${e.from} → ${e.to}',
        );
      }
    });

    test('wraps a long layer into columns: the flow is wide, not tall', () {
      final b = bounds(d);
      final o = bounds(old);
      final w = b.right - b.left;
      final h = b.bottom - b.top;
      // The old columns: three, each as tall as its blocks stacked.
      expect(o.bottom - o.top, greaterThan(3000));
      expect(h, lessThan((o.bottom - o.top) / 2));
      expect(w / h, inInclusiveRange(0.8, 3.0));
      // More columns than layers: at least one layer wrapped.
      final columns = {for (final x in d.blocks.values) x.x};
      expect(columns.length, greaterThan(3));
    });

    test('crosses fewer wires than the old columns', () {
      final now = wireCrossings(d, byType(types));
      final before = wireCrossings(old, byType(types));
      // ignore: avoid_print, the figures go to the PR.
      print('crossings: old columns $before, layered $now');
      expect(now, lessThanOrEqualTo(before));
    });

    test('a source sits one layer before the block it feeds', () {
      // `d_mode` feeds only `s_status_0`: it is the column just before it,
      // not the first one.
      final src = d.blocks['d_mode']!;
      final dst = d.blocks['s_status_0']!;
      final cmd = d.blocks['c_status']!;
      expect(src.x, greaterThan(cmd.x));
      expect(src.x, lessThan(dst.x));
    });
  });

  group('a saved layout', () {
    Map<String, Object?> withLayout(Map<String, List<int>> layout) => {
      ...large,
      'layout': layout,
    };

    test('wins: every saved block stays, even over another', () {
      final nodes = (large['nodes']! as Map<String, Object?>).keys;
      final layout = {
        for (final id in nodes) id: const [100, 100],
      };
      final d = placed(withLayout(layout));
      for (final b in d.blocks.values) {
        expect((b.x, b.y), (100.0, 100.0), reason: b.id);
      }
    });

    test('keeps its blocks; the others go under them, laid out', () {
      final d = placed(
        withLayout({
          'c_status': [400, 200],
          'e_status': [700, 260],
        }),
      );
      expect(
        (d.blocks['c_status']!.x, d.blocks['c_status']!.y),
        (
          400.0,
          200.0,
        ),
      );
      expect(
        (d.blocks['e_status']!.x, d.blocks['e_status']!.y),
        (
          700.0,
          260.0,
        ),
      );
      final savedBottom =
          260 +
          blockHeight(
            types['rising_edge'],
            d.blocks['e_status']!,
            edges: d.edges,
          );
      for (final b in d.blocks.values) {
        if (b.id != 'c_status' && b.id != 'e_status') {
          expect(b.y, greaterThan(savedBottom), reason: b.id);
          expect(b.x, greaterThanOrEqualTo(400), reason: b.id);
        }
      }
      expect(overlaps(d), isFalse);
    });

    test('a pin key is not a position', () {
      final v = Value.from(
        withLayout({
          'c_status': [400, 200],
          'c_status~pin~p:key': [1, 0],
        }),
      );
      expect(placedIdsOf(v), {'c_status'});
    });
  });

  test('Tidy up lays out every block, saved or not', () {
    final nodes = (large['nodes']! as Map<String, Object?>).keys;
    final d = flowDraftOf(
      'large',
      Value.from({
        ...large,
        'layout': {
          for (final id in nodes) id: const [100, 100],
        },
      }),
    );
    final tidy = tidyFlow(d, byType(types));
    expect(at(tidy), at(placed(large)));
    expect(overlaps(tidy), isFalse);
  });

  // The large flow's golden in `ui` (`flow_large`) draws these places: ui
  // does not see business, so they are written once to its frame file.
  //   WRITE_FLOW_LARGE=1 flutter test test/flow_layout_test.dart
  test(
    'the ui frame of the large flow is this layout',
    () {
      final d = placed(large);
      final frame = {
        'blocks': [
          for (final b in d.blocks.values)
            {
              'id': b.id,
              'type': b.type.wire,
              'role': roleOf(b.type).name,
              'x': b.x,
              'y': b.y,
              'width': blockWidthOf(roleOf(b.type)),
              'rows': [
                for (final f in rowsOf(types[b.type.wire], b, edges: d.edges))
                  {
                    'id': f.id,
                    'label': f.label,
                    'in': f.inPort,
                    'out': f.outPort,
                  },
              ],
            },
        ],
        'wires': [
          for (final e in d.edges) [e.from, e.fromPort, e.to, e.toPort],
        ],
      };
      final file = File('../ui/test/frames/flow_large.json');
      final text = '${const JsonEncoder.withIndent(' ').convert(frame)}\n';
      if (Platform.environment['WRITE_FLOW_LARGE'] == '1') {
        file.writeAsStringSync(text);
      }
      expect(file.readAsStringSync(), text);
    },
  );

  test('a custom block instance is laid out as tall as it is drawn', () {
    final def = {
      'id': 'inst',
      'version': 1,
      'blocks': {
        'wide': {
          'inputs': [
            for (var i = 0; i < 8; i++) {'name': 'i$i', 'to': 'e$i.in'},
          ],
          'outputs': [
            {'name': 'out', 'from': 'e0.on_edge'},
          ],
          'nodes': {
            for (var i = 0; i < 8; i++) 'e$i': {'type': 'rising_edge'},
          },
          'edges': <Object>[],
        },
      },
      'nodes': {
        for (var i = 0; i < 8; i++)
          's$i': {'type': 'subscribe', 'key': 'storage/s$i'},
        'w': {'type': 'block:wide'},
        'x': {'type': 'block:wide'},
        'r': {'type': 'set', 'path': 'storage/r'},
      },
      'edges': [
        for (var i = 0; i < 8; i++) ['s$i.out', 'w.i$i'],
        for (var i = 0; i < 8; i++) ['s$i.out', 'x.i$i'],
        ['w.out', 'r.in'],
      ],
    };
    final read = readFlow('inst', Value.from(def));
    final all = {
      for (final t in typesWithBlocks(types.values.toIList(), read.draft))
        t.type: t,
    };
    final d = placeFlow(read.draft, all, placed: read.placed.unlock);
    expect(
      blockHeight(all[bt('block:wide')], d.blocks['w']!, edges: d.edges),
      greaterThan(200),
    );
    expect(overlaps(d, all), isFalse);
    expect(overlaps(tidyFlow(d, all), all), isFalse);
  });

  test('a loop through a delay lays out', () {
    final d = flowDraftOf(
      'loop',
      Value.from({
        'nodes': {
          'a': {'type': 'const', 'value': 1},
          'b': {'type': 'rising_edge'},
          'c': {'type': 'rising_edge'},
        },
        'edges': [
          ['a.out', 'b.in'],
          ['b.on_edge', 'c.in'],
          ['c.on_edge', 'b.in'],
        ],
      }),
    );
    final t = tidyFlow(d, byType(types));
    expect(t.blocks['a']!.x, lessThan(t.blocks['b']!.x));
    expect(t.blocks['b']!.x, lessThan(t.blocks['c']!.x));
  });
}
