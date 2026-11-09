import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'flow_fields.dart';
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
        pins: {
          for (final l in layout.entries)
            if (pinKeyOf(l.key) case (
              final node,
              final field,
            ) when node == e.key)
              if (l.value case VArray(:final v) when v.isNotEmpty)
                field: (number(v[0]) ?? 0) != 0,
        }.lock,
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
Value defOf(FlowDraft d, int version) => Value.from(_defMap(d, version));

/// What `dataflows` ▸ `preview {def}` runs for [d]: its definition without
/// the layout and the version, so moving a block changes nothing, and with
/// an id (`draft`) when the flow has none yet. Two drafts with the same
/// preview definition run alike.
Value previewDefOf(FlowDraft d) {
  final m = _defMap(d, 0)..remove('layout');
  if (d.id.isEmpty) {
    m['id'] = 'draft';
  }
  return Value.from(m);
}

Map<String, Object?> _defMap(FlowDraft d, int version) {
  final rest = Map<String, Object?>.of(d.rest.unlock);
  final commands = d.blocks.values.any(
    (b) => b.type == 'set' || b.type == 'invoke',
  );
  if (commands && rest['permissions'] == null) {
    rest['permissions'] = {'maxperm': 'write'};
  }
  return {
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
      for (final b in d.blocks.values)
        for (final p in b.pins.entries)
          pinKey(b.id, p.key): [if (p.value) 1 else 0, 0],
    },
  };
}

// ---------- pins in the layout (flow-editor.md §12) ----------

/// What stands between a node id and a field id in a pin's layout key. A
/// node id is a key segment (letters, digits, `_`, `-`, `.`), so no node
/// is named like a pin.
const _pinMark = '~pin~';

/// The `layout` key of the pin of field [field] of block [node]:
/// `<node>~pin~<field id>` (`scale1~pin~p:k`). Its value is `[1, 0]`
/// (pinned to the block) or `[0, 0]` (taken off it); the second number is
/// not used. The engine reads `layout` as `{<key>: [x, y]}` of two finite
/// numbers and does not look at the keys (spec 06 0.2.5), so a pin travels
/// with the definition like a position does, on any broker.
String pinKey(String node, String field) => '$node$_pinMark$field';

/// The node and the field id of a pin's layout key; null for a position.
(String, String)? pinKeyOf(String key) {
  final i = key.indexOf(_pinMark);
  return i <= 0
      ? null
      : (key.substring(0, i), key.substring(i + _pinMark.length));
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
            port: str(p['port']),
            echo: boolean(p['echo']),
          ),
    ].lock,
    portTypes: {
      if (m['port_types'] case VMap(:final v))
        for (final e in v.entries) e.key: ?str(e.value),
    }.lock,
    echoInputs: boolean(m['echo_inputs']),
    takesValues: boolean(m['values']) ?? false,
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

/// Whether two node configs say the same: compared as values, so a map or
/// a list inside (`values`, `args`, `meta`) counts by its content, not by
/// identity (an `IMap` compares its entries with `==`).
bool sameCfg(IMap<String, Object?> a, IMap<String, Object?> b) =>
    identical(a, b) || Value.from(a.unlock) == Value.from(b.unlock);

// ---------- operand constants (ADR 0038 §7, spec 06 0.2.19) ----------

/// The config key of the operand constants: `values: {<port>: <value>}`.
const operandValuesKey = 'values';

/// The inputs of [b] that take a typed constant in `values`: `in` (when the
/// type has it and no parameter owns it) and the variable inputs
/// (`in.<name>` of `inputs`), for a type whose catalog says `values: true`.
/// Never a parameter's port (`in.op`, `in.precision`: the parameter's
/// config is its constant), never `stopwatch.reset` and never a variable's
/// `in` (its `value` is the constant): the catalog gives those types no
/// `values`.
List<String> operandPortsOf(NodeType? t, FlowBlock b) {
  if (t == null || !t.takesValues) {
    return const [];
  }
  final paramPorts = {
    for (final p in t.params)
      ?(p.port ?? (t.inputs.contains('in.${p.name}') ? 'in.${p.name}' : null)),
  };
  return [
    if (t.inputs.contains('in') && !paramPorts.contains('in')) 'in',
    for (final p in portsOf(t, b).inputs)
      if (!t.inputs.contains(p) && !paramPorts.contains(p)) p,
  ];
}

/// The constants of [b]'s operands, by port (`{in.0: "AHU-"}`).
Map<String, Object?> operandValuesOf(FlowBlock b) =>
    switch (b.cfg[operandValuesKey]) {
      final Map<Object?, Object?> m => {
        for (final e in m.entries)
          if (e.key case final String k) k: e.value,
      },
      _ => const {},
    };

/// The constant typed into operand [port] of [b], or null.
Object? operandValueOf(FlowBlock b, String port) => operandValuesOf(b)[port];

/// [b]'s config with [value] as the constant of operand [port] (null or
/// empty text removes it; an empty map removes `values`). Null when [port]
/// takes no constant ([operandPortsOf]): the engine refuses it at compile
/// (`values.<port>: not an operand input`).
IMap<String, Object?>? cfgWithOperandValue(
  NodeType? t,
  FlowBlock b,
  String port,
  Object? value,
) {
  if (!operandPortsOf(t, b).contains(port)) {
    return null;
  }
  final m = Map<String, Object?>.of(operandValuesOf(b));
  if (value == null || value == '') {
    m.remove(port);
  } else {
    m[port] = value;
  }
  return m.isEmpty
      ? b.cfg.remove(operandValuesKey)
      : b.cfg.add(operandValuesKey, m);
}

/// [cfg] without the constants of [ports] (inputs a resize removed).
IMap<String, Object?> cfgWithoutOperands(
  IMap<String, Object?> cfg,
  Iterable<String> ports,
) {
  final b = FlowBlock(id: '', type: '', cfg: cfg);
  final m = Map<String, Object?>.of(operandValuesOf(b));
  if (!ports.any(m.containsKey)) {
    return cfg;
  }
  ports.forEach(m.remove);
  return m.isEmpty
      ? cfg.remove(operandValuesKey)
      : cfg.add(operandValuesKey, m);
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

/// [d] with its blocks laid out in columns by depth (sources left, sinks
/// right) when the stored layout overlaps at the editor's block sizes; else
/// [d] as it is.
FlowDraft tidyIfOverlapping(FlowDraft d, Map<String, NodeType> types) {
  final rects = {
    for (final b in d.blocks.values)
      b.id: (
        b.x,
        b.y,
        b.x + blockWidthOf(roleOf(b.type)),
        b.y + blockHeight(types[b.type], b, edges: d.edges),
      ),
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
    blocks[b.id] = b.copyWith(x: 40 + 300.0 * col, y: top);
    y[col] = top + blockHeight(types[b.type], b, edges: d.edges) + 28;
  }
  return d.copyWith(blocks: blocks.lock);
}
