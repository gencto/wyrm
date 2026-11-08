import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// A `~def` (spec 06) as a [FlowDraft].
FlowDraft flowDraftOf(String id, Value def) {
  final layout = switch (def['layout']) {
    VMap(:final v) => v,
    _ => const <String, Value>{},
  };
  final blocks = <String, FlowBlock>{};
  var i = 0;
  if (def['nodes'] case VMap(:final v)) {
    for (final e in v.entries) {
      final cfg = switch (toDart(e.value)) {
        final Map<String, Object?> m => Map.of(m),
        _ => <String, Object?>{},
      };
      final type = cfg.remove('type') as String? ?? '';
      final xy = layout[e.key];
      final (x, y) = switch (xy) {
        VArray(:final v) when v.length == 2 => (
          (number(v[0]) ?? 0).toDouble(),
          (number(v[1]) ?? 0).toDouble(),
        ),
        _ => (40.0 + 260 * (i % 4), 40.0 + 200 * (i ~/ 4)),
      };
      blocks[e.key] = FlowBlock(
        id: e.key,
        type: type,
        cfg: cfg.lock,
        x: x,
        y: y,
      );
      i++;
    }
  }
  final edges = <FlowEdge>[];
  if (def['edges'] case VArray(:final v)) {
    for (final pair in v) {
      final a = endpoint(
        str(pair is VArray && pair.v.isNotEmpty ? pair.v[0] : null),
      );
      final b = endpoint(
        str(pair is VArray && pair.v.length > 1 ? pair.v[1] : null),
      );
      if (a != null && b != null) {
        edges.add(FlowEdge(from: a.$1, fromPort: a.$2, to: b.$1, toPort: b.$2));
      }
    }
  }
  final rest = <String, Object?>{
    for (final e in (def is VMap ? def.v : const <String, Value>{}).entries)
      if (!const ['id', 'version', 'nodes', 'edges', 'layout'].contains(e.key))
        e.key: toDart(e.value),
  };
  return FlowDraft(
    id: id,
    version: integer(def['version']) ?? 0,
    blocks: blocks.lock,
    edges: edges.lock,
    rest: rest.lock,
  );
}

/// `<node>.<port>` split at the first dot (`in.<name>` ports keep theirs).
(String, String)? endpoint(String? s) {
  if (s == null) {
    return null;
  }
  final i = s.indexOf('.');
  return i <= 0 ? null : (s.substring(0, i), s.substring(i + 1));
}

/// The definition of [d] at [version], with the editor's layout; a flow
/// that sets or invokes gets `permissions.maxperm: write` when it has none
/// (spec 06 rule 7).
Value defOf(FlowDraft d, int version) {
  final rest = Map<String, Object?>.of(d.rest.unlock);
  final commands = d.blocks.values.any(
    (b) => b.type == 'set' || b.type == 'invoke',
  );
  if (commands && rest['permissions'] == null) {
    rest['permissions'] = {'maxperm': 'write'};
  }
  return Value.from({
    ...rest,
    'id': d.id,
    'version': version,
    'nodes': {
      for (final b in d.blocks.values) b.id: {'type': b.type, ...b.cfg.unlock},
    },
    'edges': [
      for (final e in d.edges)
        ['${e.from}.${e.fromPort}', '${e.to}.${e.toPort}'],
    ],
    'layout': {
      for (final b in d.blocks.values) b.id: [b.x.round(), b.y.round()],
    },
  });
}

/// One entry of `node_types`.
NodeType nodeTypeOf(Value m) {
  List<String> texts(Value? v) => switch (v) {
    VArray(:final v) => [for (final x in v) ?str(x)],
    _ => const [],
  };
  final dynIn = m['dyn_inputs'];
  final dynOut = m['dyn_outputs'];
  return NodeType(
    type: str(m['type']) ?? '',
    category: str(m['category']) ?? '',
    description: str(m['description']) ?? '',
    inputs: texts(m['inputs']).lock,
    outputs: texts(m['outputs']).lock,
    dynInParam: str(dynIn?['param']),
    dynInPrefix: str(dynIn?['prefix']) ?? '',
    dynInDefaults: texts(dynIn?['default']).lock,
    dynOutParam: str(dynOut?['param']),
    dynOutPrefix: str(dynOut?['prefix']) ?? '',
    dynOutDefaults: texts(dynOut?['default']).lock,
    params: [
      if (m['params'] case VArray(:final v))
        for (final p in v)
          ParamSpec(
            name: str(p['name']) ?? '',
            type: str(p['type']) ?? 'string',
            required: boolean(p['required']) ?? false,
            description: str(p['description']),
            choices: texts(p['choices']).lock,
            defaultValue: toDart(p['default']),
            editor: str(p['editor']),
          ),
    ].lock,
  );
}

/// The ports of [b] by its type: fixed ones and the ones a parameter names.
({List<String> inputs, List<String> outputs}) portsOf(
  NodeType? t,
  FlowBlock b,
) {
  if (t == null) {
    return (inputs: const ['in'], outputs: const ['out']);
  }
  List<String> dyn(String? param, String prefix, IList<String> defaults) {
    if (param == null) {
      return const [];
    }
    final names = switch (b.cfg[param]) {
      final List<Object?> l => [
        for (final n in l)
          if (n is String && n.isNotEmpty) n,
      ],
      final Map<String, Object?> m => m.keys.toList(),
      _ => <String>[],
    };
    return [for (final n in names.isEmpty ? defaults : names) '$prefix$n'];
  }

  return (
    inputs: [...t.inputs, ...dyn(t.dynInParam, t.dynInPrefix, t.dynInDefaults)],
    outputs: [
      ...t.outputs,
      ...dyn(t.dynOutParam, t.dynOutPrefix, t.dynOutDefaults),
    ],
  );
}

/// The keys a flow reads (`subscribe` keys) and writes (`set`, `invoke`,
/// `publish` targets), relative to the site.
({List<String> reads, List<String> writes}) flowKeysOf(FlowDraft d) => (
  reads: [
    for (final b in d.blocks.values)
      if (b.type == 'subscribe' || b.type == 'liveliness')
        if (b.cfg['key'] case final String k) k,
  ],
  writes: [
    for (final b in d.blocks.values)
      if (const {'set', 'invoke', 'publish'}.contains(b.type))
        if (b.cfg['key'] ?? b.cfg['target'] case final String k) k,
  ],
);

/// A map or list parameter as the JSON text its field shows.
String flowJson(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

/// The JSON text of a map or list field back as a value.
Object? flowJsonDecode(String s) => jsonDecode(s);

/// The height the editor draws block [b] at (header, rows, padding).
double blockHeight(NodeType? t, FlowBlock b) {
  final p = portsOf(t, b);
  final rows = p.inputs.length + p.outputs.length;
  return 38 + 16 + 28.0 * (rows == 0 ? 1 : rows) + 30;
}

/// [d] with its blocks laid out in columns by depth (sources left, sinks
/// right) when the stored layout overlaps at the editor's block sizes; else
/// [d] as it is.
FlowDraft tidyIfOverlapping(FlowDraft d, Map<String, NodeType> types) {
  const w = 230.0;
  final rects = {
    for (final b in d.blocks.values)
      b.id: (b.x, b.y, b.x + w, b.y + blockHeight(types[b.type], b)),
  };
  var overlap = false;
  final list = rects.values.toList();
  for (var i = 0; i < list.length && !overlap; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final a = list[i];
      final c = list[j];
      if (a.$1 < c.$3 && c.$1 < a.$3 && a.$2 < c.$4 && c.$2 < a.$4) {
        overlap = true;
        break;
      }
    }
  }
  if (!overlap) {
    return d;
  }
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
    blocks[b.id] = b.copyWith(x: 40 + 290.0 * col, y: top);
    y[col] = top + blockHeight(types[b.type], b) + 28;
  }
  return d.copyWith(blocks: blocks.lock);
}
