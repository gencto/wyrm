import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';

import 'flow_fields.dart';

// The automatic layout of a flow (flow-editor.md §25): blocks in layers by
// the data flow (sources left, commands right), a long layer wrapped into
// several columns, the blocks of a layer in the order that crosses the
// fewest wires, each block level with the fields it is wired to. The same
// definition always gives the same layout: nothing here reads the view, a
// clock or the order of a map.

/// Where the first block's top-left corner lands.
const layoutOrigin = 40.0;

/// The grid every position snaps to (the canvas's, spec §4).
const layoutGrid = 20.0;

/// Between two layers: room for the wires.
const layoutLayerGap = 120.0;

/// Between two columns of one wrapped layer.
const layoutColumnGap = 40.0;

/// Between two blocks of one column.
const layoutRowGap = 40.0;

/// The shape the layout aims at: width / height of the whole flow. A
/// layer taller than the flow's share of it wraps into columns.
const layoutAspect = 1.2;

/// Below a saved layout, where the blocks without a position go.
const layoutBelowGap = 80.0;

/// [d] with a place for every block [placed] does not name. A saved
/// position always wins: with every block placed, [d] is returned as it
/// is; with none, the whole flow is laid out ([tidyFlow]); else only the
/// blocks without one are laid out, among themselves, under the saved ones.
FlowDraft placeFlow(
  FlowDraft d,
  Map<BlockType, NodeType> types, {
  required Set<String> placed,
}) {
  final open = {
    for (final id in d.blocks.keys)
      if (!placed.contains(id)) id,
  };
  if (open.isEmpty) {
    return d;
  }
  if (open.length == d.blocks.length) {
    return tidyFlow(d, types);
  }
  final kept = [
    for (final b in d.blocks.values)
      if (!open.contains(b.id)) b,
  ];
  final left = kept.map((b) => b.x).reduce(math.min);
  final bottom = kept
      .map((b) => b.y + blockHeight(types[b.type], b, edges: d.edges))
      .reduce(math.max);
  final at = _layout(d, types, open);
  return _moved(
    d,
    at.map(
      (id, p) => MapEntry(id, (
        _snap(p.$1 - layoutOrigin + left),
        _snap(p.$2 - layoutOrigin + bottom + layoutBelowGap),
      )),
    ),
  );
}

/// Every block of [d] laid out by the data flow (`Tidy up`, spec §25).
FlowDraft tidyFlow(FlowDraft d, Map<BlockType, NodeType> types) =>
    _moved(d, _layout(d, types, d.blocks.keys.toSet()));

FlowDraft _moved(FlowDraft d, Map<String, (double, double)> at) {
  if (at.isEmpty) {
    return d;
  }
  return d.copyWith(
    blocks: {
      for (final b in d.blocks.values)
        b.id: switch (at[b.id]) {
          (final x, final y) => b.copyWith(x: x, y: y),
          null => b,
        },
    }.lock,
  );
}

double _snap(double v) => (v / layoutGrid).round() * layoutGrid;

/// How many wires of [d] cross on the canvas, each drawn as a straight
/// line from its output's port to its input's port. Two wires that share
/// a port do not count. What the layout makes few; tests compare layouts
/// with it.
int wireCrossings(FlowDraft d, Map<BlockType, NodeType> types) {
  final g = _Geometry(d, types);
  final segs = [
    for (final e in d.edges)
      if (g.port(e.from, e.fromPort, output: true) case final a?)
        if (g.port(e.to, e.toPort, output: false) case final b?)
          (a, b, '${e.from}.${e.fromPort}', '${e.to}.${e.toPort}'),
  ];
  var n = 0;
  for (var i = 0; i < segs.length; i++) {
    for (var j = i + 1; j < segs.length; j++) {
      final s = segs[i];
      final t = segs[j];
      if (s.$3 == t.$3 || s.$4 == t.$4) {
        continue;
      }
      if (_cross(s.$1, s.$2, t.$1, t.$2)) {
        n++;
      }
    }
  }
  return n;
}

bool _cross(
  (double, double) a,
  (double, double) b,
  (double, double) c,
  (double, double) d,
) {
  double side((double, double) p, (double, double) q, (double, double) r) =>
      (q.$1 - p.$1) * (r.$2 - p.$2) - (q.$2 - p.$2) * (r.$1 - p.$1);
  final d1 = side(c, d, a);
  final d2 = side(c, d, b);
  final d3 = side(a, b, c);
  final d4 = side(a, b, d);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// The size of each block and the place of each port in it.
final class _Geometry {
  _Geometry(this.d, this.types);

  final FlowDraft d;
  final Map<BlockType, NodeType> types;
  final _rows = <String, List<FlowField>>{};

  List<FlowField> rows(FlowBlock b) =>
      _rows[b.id] ??= rowsOf(types[b.type], b, edges: d.edges);

  double width(FlowBlock b) => blockWidthOf(roleOf(b.type));

  double height(FlowBlock b) => blockHeight(types[b.type], b, edges: d.edges);

  /// How far below the block's top the port [port] is: the middle of its
  /// row (header 32, body padding 6, rows of 28); the block's middle when
  /// no row has it.
  double portDy(FlowBlock b, String port, {required bool output}) {
    final rs = rows(b);
    final i = rs.indexWhere(
      (f) => output ? f.sends(port) : f.inPort == port,
    );
    return i < 0 ? height(b) / 2 : 32 + 6 + 28.0 * i + 14;
  }

  (double, double)? port(String id, String port, {required bool output}) {
    final b = d.blocks[id];
    if (b == null) {
      return null;
    }
    return (
      b.x + (output ? width(b) : 0),
      b.y + portDy(b, port, output: output),
    );
  }
}

/// One edge of the layered graph: from block `from`'s port at `fromDy`
/// below its top to block `to`'s port at `toDy`.
typedef _Link = ({String from, String to, double fromDy, double toDy});

/// The top-left corners of the blocks [ids] of [d], laid out among
/// themselves from [layoutOrigin].
Map<String, (double, double)> _layout(
  FlowDraft d,
  Map<BlockType, NodeType> types,
  Set<String> ids,
) {
  if (ids.isEmpty) {
    return const {};
  }
  final g = _Geometry(d, types);
  final nodes = ids.toList()..sort();
  final blocks = {for (final id in nodes) id: d.blocks[id]!};
  // Edges among the blocks, in a fixed order; a block's wire to itself
  // says nothing of where it goes.
  final edges =
      [
        for (final e in d.edges)
          if (e.from != e.to && ids.contains(e.from) && ids.contains(e.to)) e,
      ]..sort(
        (a, b) => _edgeKey(a).compareTo(_edgeKey(b)),
      );
  final links = [
    for (final e in _acyclic(nodes, edges))
      (
        from: e.from,
        to: e.to,
        fromDy: g.portDy(blocks[e.from]!, e.fromPort, output: true),
        toDy: g.portDy(blocks[e.to]!, e.toPort, output: false),
      ),
  ];
  final layers = _layers(nodes, links);
  final heights = {for (final id in nodes) id: g.height(blocks[id]!)};
  final widths = {for (final id in nodes) id: g.width(blocks[id]!)};

  // The flow's height: the area of every block with its gaps, at the
  // aspect the layout aims at; never less than the tallest block.
  final area = nodes.fold<double>(
    0,
    (s, id) =>
        s + (widths[id]! + layoutColumnGap) * (heights[id]! + layoutRowGap),
  );
  final tallest = heights.values.reduce(math.max);
  final limit = math.max(tallest, math.sqrt(area / layoutAspect));

  final placer = _Placer(
    layers: layers,
    links: links,
    widths: widths,
    heights: heights,
    limit: limit,
  );
  return placer.run();
}

String _edgeKey(FlowEdge e) =>
    '${e.from}\u0000${e.fromPort}\u0000'
    '${e.to}\u0000${e.toPort}';

/// [edges] without the ones that close a loop (a `delay` may): a depth
/// first walk from each block in id order drops an edge back to a block
/// still on its path.
List<FlowEdge> _acyclic(List<String> nodes, List<FlowEdge> edges) {
  final out = <String, List<FlowEdge>>{};
  for (final e in edges) {
    (out[e.from] ??= []).add(e);
  }
  final state = <String, int>{}; // 1: on the path, 2: done
  final keep = <FlowEdge>[];
  void walk(String id) {
    state[id] = 1;
    for (final e in out[id] ?? const <FlowEdge>[]) {
      switch (state[e.to]) {
        case 1:
          break; // back to the path: a loop
        case 2:
          keep.add(e);
        default:
          keep.add(e);
          walk(e.to);
      }
    }
    state[id] = 2;
  }

  for (final id in nodes) {
    if (state[id] == null) {
      walk(id);
    }
  }
  return keep..sort((a, b) => _edgeKey(a).compareTo(_edgeKey(b)));
}

/// The layer of each block: one past the deepest block that feeds it; a
/// block nothing feeds sits one layer before its first consumer, so its
/// wires stay short. Empty layers are dropped.
List<List<String>> _layers(List<String> nodes, List<_Link> links) {
  final preds = <String, List<String>>{};
  final succs = <String, List<String>>{};
  for (final l in links) {
    (preds[l.to] ??= []).add(l.from);
    (succs[l.from] ??= []).add(l.to);
  }
  final layer = <String, int>{};
  int depth(String id) {
    if (layer[id] case final n?) {
      return n;
    }
    final p = preds[id] ?? const <String>[];
    final n = p.isEmpty ? 0 : p.map(depth).reduce(math.max) + 1;
    return layer[id] = n;
  }

  nodes.forEach(depth);
  for (final id in nodes) {
    final s = succs[id];
    if ((preds[id] ?? const []).isEmpty && s != null) {
      layer[id] = math.max(0, s.map((x) => layer[x]!).reduce(math.min) - 1);
    }
  }
  final used = layer.values.toSet().toList()..sort();
  return [
    for (final n in used)
      [
        for (final id in nodes)
          if (layer[id] == n) id,
      ],
  ];
}

/// Orders the blocks of each layer, wraps it into columns and gives each
/// block its place.
final class _Placer {
  _Placer({
    required this.layers,
    required this.links,
    required this.widths,
    required this.heights,
    required this.limit,
  }) {
    for (final l in links) {
      (_in[l.to] ??= []).add(l);
      (_out[l.from] ??= []).add(l);
    }
  }

  final List<List<String>> layers;
  final List<_Link> links;
  final Map<String, double> widths;
  final Map<String, double> heights;

  /// How tall a column may grow before its layer wraps.
  final double limit;

  final _in = <String, List<_Link>>{};
  final _out = <String, List<_Link>>{};

  /// Barycenter sweeps: down, up, down, … The order that crosses the
  /// fewest wires wins (the first of equals).
  static const sweeps = 8;

  Map<String, (double, double)> run() {
    var order = [for (final l in layers) List.of(l)];
    var at = _place(order);
    var best = at;
    var fewest = _crossings(at);
    for (var i = 0; i < sweeps && fewest > 0; i++) {
      order = _sweep(order, at, down: i.isEven);
      at = _place(order);
      final n = _crossings(at);
      if (n < fewest) {
        fewest = n;
        best = at;
      }
    }
    return best;
  }

  /// Each layer sorted by the mean height of the ports it is wired to on
  /// the side the sweep comes from; a block with none keeps its height.
  List<List<String>> _sweep(
    List<List<String>> order,
    Map<String, (double, double)> at, {
    required bool down,
  }) {
    final next = <List<String>>[];
    for (final layer in order) {
      double key(String id) {
        final ls = down ? _in[id] : _out[id];
        if (ls == null || ls.isEmpty) {
          return at[id]!.$2 + heights[id]! / 2;
        }
        var sum = 0.0;
        for (final l in ls) {
          sum += down
              ? at[l.from]!.$2 + l.fromDy - l.toDy
              : at[l.to]!.$2 + l.toDy - l.fromDy;
        }
        return sum / ls.length;
      }

      final keys = {for (final id in layer) id: key(id)};
      next.add(
        List.of(layer)..sort((a, b) {
          final c = keys[a]!.compareTo(keys[b]!);
          return c != 0 ? c : a.compareTo(b);
        }),
      );
    }
    return next;
  }

  /// The places of the blocks for [order]: layer after layer from the
  /// left; a layer taller than [limit] wraps into columns, each block into
  /// the column that ends highest; then each column's blocks move level
  /// with the ports they are wired to, in their order and never closer
  /// than [layoutRowGap].
  Map<String, (double, double)> _place(List<List<String>> order) {
    final x = <String, double>{};
    final y = <String, double>{};
    final columns = <List<String>>[];
    var left = layoutOrigin;
    for (final layer in order) {
      final total = layer.fold<double>(
        0,
        (s, id) => s + heights[id]! + layoutRowGap,
      );
      final count = math.max(1, (total / (limit + layoutRowGap)).ceil());
      final cols = [for (var i = 0; i < count; i++) <String>[]];
      final ends = List<double>.filled(count, layoutOrigin);
      for (final id in layer) {
        var c = 0;
        for (var i = 1; i < count; i++) {
          if (ends[i] < ends[c]) {
            c = i;
          }
        }
        cols[c].add(id);
        y[id] = ends[c];
        ends[c] += heights[id]! + layoutRowGap;
      }
      final width = layer.map((id) => widths[id]!).reduce(math.max);
      for (final (i, col) in cols.indexed) {
        for (final id in col) {
          x[id] = left + i * (width + layoutColumnGap);
        }
        if (col.isNotEmpty) {
          columns.add(col);
        }
      }
      left +=
          count * (width + layoutColumnGap) - layoutColumnGap + layoutLayerGap;
    }
    // Level with the wires: from the left with the blocks before, then
    // from the right with the blocks after and before.
    for (final col in columns) {
      _level(col, y, (id) => _in[id] ?? const [], fromLeft: true);
    }
    for (final col in columns.reversed) {
      _level(
        col,
        y,
        (id) => [...?_in[id], ...?_out[id]],
        fromLeft: false,
      );
    }
    return {
      for (final id in x.keys) id: (_snap(x[id]!), _snap(y[id]!)),
    };
  }

  /// Moves the blocks of [col] (top to bottom) as close as they may come
  /// to the heights their wires [linksOf] ask for, keeping their order and
  /// gaps (an isotonic regression, pool adjacent violators), never above
  /// [layoutOrigin].
  void _level(
    List<String> col,
    Map<String, double> y,
    List<_Link> Function(String id) linksOf, {
    required bool fromLeft,
  }) {
    // Offsets of each block from the column's first one when packed.
    final offset = <double>[];
    var o = 0.0;
    for (final id in col) {
      offset.add(o);
      o += heights[id]! + layoutRowGap;
    }
    final want = <double>[];
    for (final (i, id) in col.indexed) {
      final ls = linksOf(id);
      var sum = 0.0;
      var n = 0;
      for (final l in ls) {
        if (l.to == id && y[l.from] != null) {
          sum += y[l.from]! + l.fromDy - l.toDy;
          n++;
        } else if (l.from == id && y[l.to] != null) {
          sum += y[l.to]! + l.toDy - l.fromDy;
          n++;
        }
      }
      want.add((n == 0 ? y[id]! : sum / n) - offset[i]);
    }
    // Pool adjacent violators: the nondecreasing sequence nearest [want].
    final means = <double>[];
    final sizes = <int>[];
    for (final w in want) {
      means.add(w);
      sizes.add(1);
      while (means.length > 1 && means[means.length - 2] > means.last) {
        final m = means.removeLast();
        final s = sizes.removeLast();
        final pm = means.removeLast();
        final ps = sizes.removeLast();
        means.add((pm * ps + m * s) / (ps + s));
        sizes.add(ps + s);
      }
    }
    var i = 0;
    for (final (k, m) in means.indexed) {
      for (var j = 0; j < sizes[k]; j++, i++) {
        y[col[i]] = math.max(layoutOrigin, m) + offset[i];
      }
    }
  }

  int _crossings(Map<String, (double, double)> at) {
    final segs = [
      for (final l in links)
        (
          at[l.from]!.$1 + widths[l.from]!,
          at[l.from]!.$2 + l.fromDy,
          at[l.to]!.$1,
          at[l.to]!.$2 + l.toDy,
          l,
        ),
    ];
    var n = 0;
    for (var i = 0; i < segs.length; i++) {
      for (var j = i + 1; j < segs.length; j++) {
        final s = segs[i];
        final t = segs[j];
        if ((s.$5.from == t.$5.from && s.$5.fromDy == t.$5.fromDy) ||
            (s.$5.to == t.$5.to && s.$5.toDy == t.$5.toDy)) {
          continue;
        }
        if (_cross((s.$1, s.$2), (s.$3, s.$4), (t.$1, t.$2), (t.$3, t.$4))) {
          n++;
        }
      }
    }
    return n;
  }
}
