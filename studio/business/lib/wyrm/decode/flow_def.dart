import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_def.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/json_value.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'block_def.dart';
import 'decoded.dart';
import 'flow_permissions.dart';

// A flow's definition (spec 06 `~def`) both ways: read once into a
// [FlowDraft] ([flowReadOf]), and written back as the engine takes it
// ([defOf], [previewDefOf], [defJsonOf]). Nothing else in Studio reads or
// writes the shape.

const _shape = 'flow def';

/// A definition read: the draft and the ids of the blocks its `layout`
/// gives a place (the others stand on a grid until they are laid out,
/// flow-editor.md §25).
final class FlowRead {
  const FlowRead(this.draft, this.placed);

  final FlowDraft draft;
  final ISet<String> placed;

  @override
  bool operator ==(Object other) =>
      other is FlowRead && other.draft == draft && other.placed == placed;

  @override
  int get hashCode => Object.hash(draft, placed);
}

/// A `~def` (spec 06) as a [FlowDraft] of flow [id].
///
/// [Invalid], with the field, when the definition is no map; when
/// `nodes`, `edges` or `layout` is there and is not a map, an array and a
/// map; when a node is no map or names no `type`; when an edge is not two
/// `<node>.<port>` texts; when `version` is not a whole number; when
/// `blocks` is not a map of custom blocks that read ([blockDefOf]: the
/// field is `blocks.<name>.<field>`). Nothing of
/// a broken definition is dropped in silence: the caller keeps what it
/// had and says why.
///
/// Read leniently, each with a warning naming the field: a position in
/// `layout` that is not two numbers (the block stands on the grid); a
/// pin whose field is no field id (it is not kept); `permissions` that do
/// not decode (none named).
Decoded<FlowRead> flowReadOf(String id, Value def) {
  try {
    return Valid(_read(id, def));
  } on _Bad catch (b) {
    return Invalid(_shape, b.field, b.reason);
  }
}

FlowRead _read(String id, Value def) {
  if (def is! VMap) {
    throw const _Bad('', 'not a map');
  }
  // A definition is JSON (spec 06): a value it has no form for (bytes) is
  // refused here, with its field, so nothing the view reads meets one.
  _jsonOnly(def, '');
  final layout = switch (def['layout']) {
    null || VNull() => const <String, Value>{},
    VMap(:final v) => v,
    _ => throw const _Bad('layout', 'not a map'),
  };
  final nodes = switch (def['nodes']) {
    null || VNull() => const <String, Value>{},
    VMap(:final v) => v,
    _ => throw const _Bad('nodes', 'not a map'),
  };
  // The pins of the layout, by node (`<node>~pin~<field>`, [pinKey]).
  final pins = <String, Map<String, bool>>{};
  for (final MapEntry(:key, :value) in layout.entries) {
    final i = key.indexOf(_pinMark);
    if (i <= 0) {
      continue;
    }
    final node = key.substring(0, i);
    final field = RowId.fromKey(key.substring(i + _pinMark.length));
    final on = switch (value) {
      VArray(:final v) when v.isNotEmpty => number(v.first),
      _ => null,
    };
    if (field is! FieldId || on == null) {
      _warn(id, 'layout.$key', 'not a pin');
      continue;
    }
    (pins[node] ??= {})[field.key] = on != 0;
  }
  final placed = <String>{};
  final blocks = <String, FlowBlock>{};
  var i = 0;
  for (final MapEntry(key: node, value: v) in nodes.entries) {
    final cfg = switch (toDart(v)) {
      final Map<String, Object?> m => Map.of(m),
      _ => throw _Bad('nodes.$node', 'not a map'),
    };
    final type = switch (cfg.remove('type')) {
      final String t when t.isNotEmpty => t,
      _ => throw _Bad('nodes.$node.type', 'missing'),
    };
    for (final MapEntry(:key, :value) in cfg.entries) {
      _bounded(value, 'nodes.$node.$key');
    }
    final saved = switch (layout[node]) {
      null => null,
      VArray(:final v) when v.length == 2 => switch ((
        number(v[0]),
        number(v[1]),
      )) {
        (final x?, final y?) => (x.toDouble(), y.toDouble()),
        _ => _warn(id, 'layout.$node', 'not two numbers'),
      },
      _ => _warn(id, 'layout.$node', 'not two numbers'),
    };
    if (saved != null) {
      placed.add(node);
    }
    final (x, y) = saved ?? (40.0 + 260 * (i % 4), 40.0 + 200 * (i ~/ 4));
    blocks[node] = FlowBlock(
      id: node,
      type: BlockType.fromWire(type),
      cfg: cfg.lock,
      x: x,
      y: y,
      pins: (pins[node] ?? const {}).lock,
    );
    i++;
  }
  final edges = <FlowEdge>[];
  switch (def['edges']) {
    case null || VNull():
      break;
    case VArray(:final v):
      for (final (n, pair) in v.indexed) {
        final ends = switch (pair) {
          VArray(v: [VStr(v: final a), VStr(v: final b)]) => (
            portEndOf(a),
            portEndOf(b),
          ),
          _ => throw _Bad('edges[$n]', 'not two texts'),
        };
        switch (ends) {
          case (final a?, final b?):
            edges.add(FlowEdge.between(a, b));
          default:
            throw _Bad('edges[$n]', 'not <node>.<port>');
        }
      }
    default:
      throw const _Bad('edges', 'not an array');
  }
  // The custom blocks: each read here, so a broken one refuses the flow
  // with its field, as a broken node does.
  final defs = <String, BlockDef>{};
  switch (def['blocks']) {
    case null || VNull():
      break;
    case VMap(:final v):
      for (final MapEntry(:key, :value) in v.entries) {
        switch (toDart(value)) {
          case final Map<String, Object?> m:
            switch (blockDefOf(m)) {
              case Valid(value: final d):
                defs[key] = d;
              case Invalid(:final field, :final reason):
                throw _Bad(
                  field.isEmpty ? 'blocks.$key' : 'blocks.$key.$field',
                  reason,
                );
            }
          default:
            throw _Bad('blocks.$key', 'not a map');
        }
      }
    default:
      throw const _Bad('blocks', 'not a map');
  }
  final version = switch (def['version']) {
    null || VNull() => 0,
    final v =>
      integer(v) ?? (throw const _Bad('version', 'not a whole number')),
  };
  return FlowRead(
    FlowDraft(
      id: id,
      version: version,
      blocks: blocks.lock,
      edges: edges.lock,
      rest: {
        for (final e in def.v.entries)
          if (!_own.contains(e.key)) e.key: _bounded(toDart(e.value), e.key),
      }.lock,
      defs: defs.lock,
      description: switch (def['description']) {
        VStr(:final v) => v,
        _ => null,
      },
      permissions: flowPermissionsOf(def['permissions']).orWarn('flow $id'),
    ),
    placed.lock,
  );
}

/// The keys the draft holds itself; every other key of the definition is
/// kept as it came in [FlowDraft.rest].
const _own = {'id', 'version', 'nodes', 'edges', 'layout', 'blocks'};

/// The newest definition of flow [id] in its `history` answer (an array of
/// definitions, oldest first); null when it has none. [Invalid] when the
/// answer is no array, or the newest definition does not read.
Decoded<FlowRead?> newestFlowOf(String id, Value history) => switch (history) {
  VNull() || VArray(v: []) => const Valid(null),
  VArray(:final v) => switch (flowReadOf(id, v.last)) {
    Valid(:final value) => Valid(value),
    Invalid(:final field, :final reason) => Invalid(_shape, field, reason),
  },
  _ => const Invalid('flow history', '', 'not an array'),
};

/// `<node>.<port>` split at the first dot (`in.<name>` ports keep theirs);
/// null when it is not one.
PortEnd? portEndOf(String? s) {
  if (s == null) {
    return null;
  }
  final i = s.indexOf('.');
  return i <= 0 || i == s.length - 1
      ? null
      : PortEnd(s.substring(0, i), s.substring(i + 1));
}

(double, double)? _warn(String id, String field, String reason) {
  decodeLog.warning('flow $id: $_shape.$field: $reason');
  return null;
}

/// Throws, naming its field ([at]), when [v] holds a value JSON has no
/// form for (bytes) at any depth.
void _jsonOnly(Value v, String at, [int depth = 0]) {
  if (depth > _deepest) {
    throw _Bad(at, 'nested too deep');
  }
  switch (v) {
    case VBytes():
      throw _Bad(at, 'not JSON');
    case VArray(:final v):
      for (final (i, x) in v.indexed) {
        _jsonOnly(x, '$at[$i]', depth + 1);
      }
    case VMap(:final v):
      for (final MapEntry(:key, :value) in v.entries) {
        _jsonOnly(value, at.isEmpty ? key : '$at.$key', depth + 1);
      }
    case VNull() || VBool() || VInt() || VFloat() || VStr():
      break;
  }
}

/// The deepest [_jsonOnly] walks a definition: a value may nest as deep
/// as [JsonValue.maxDepth] (each is checked on its own, [_bounded]), and a
/// definition puts a few levels around it (`blocks.<b>.nodes.<n>.<key>`).
/// Past this it is refused before it is walked further.
const int _deepest = JsonValue.maxDepth + 8;

/// [v] (a value of a node's config, or of the definition's own fields),
/// refused with its field [at] when it nests deeper than
/// [JsonValue.maxDepth]: the editor reads each such value as JSON while it
/// builds, so none past the bound may come in.
Object? _bounded(Object? v, String at) =>
    JsonValue.isJson(v) ? v : throw _Bad(at, 'nested too deep');

final class _Bad implements Exception {
  const _Bad(this.field, this.reason);

  final String field;
  final String reason;
}

// ---------- the other way: the definition of a draft ----------

/// The definition of [d] at [version], with the editor's layout; a flow
/// that sets or invokes gets `permissions.maxperm: write` when it has none
/// (spec 06 rule 7).
Value defOf(FlowDraft d, int version) => Value.from(defJsonOf(d, version));

/// What `dataflows` ▸ `preview {def}` runs for [d]: its definition without
/// the layout and the version, so moving a block changes nothing, and with
/// an id (`draft`) when the flow has none yet. Two drafts with the same
/// preview definition run alike.
Value previewDefOf(FlowDraft d) {
  final m = defJsonOf(d, 0)..remove('layout');
  if (d.id.isEmpty) {
    m['id'] = 'draft';
  }
  return Value.from(m);
}

/// The arguments of a call that takes a definition: `{def}` (`deploy`,
/// `validate`), with `max_hz` for `preview`.
Value defArgs(Value def, {int? maxHz}) => VMap({
  'def': def,
  if (maxHz != null) 'max_hz': VInt(maxHz),
});

/// The definition of [d] at [version] as JSON values (a map of texts,
/// numbers, lists and maps): what [defOf] encodes.
Map<String, Object?> defJsonOf(FlowDraft d, int version) {
  final rest = Map<String, Object?>.of(d.rest.unlock);
  final commands = d.blocks.values.any(
    (b) => b.type.known == KnownBlock.set || b.type.known == KnownBlock.invoke,
  );
  if (commands && rest['permissions'] == null) {
    rest['permissions'] = {'maxperm': Perm.write.wire};
  }
  return {
    ...rest,
    if (d.defs.isNotEmpty) 'blocks': blockDefsJsonOf(d.defs),
    'id': d.id,
    'version': version,
    'nodes': nodesJsonOf(d),
    'edges': edgesJsonOf(d),
    'layout': layoutJsonOf(d),
  };
}

/// `nodes` of [d]'s definition: each block's config with its `type`.
Map<String, Map<String, Object?>> nodesJsonOf(FlowDraft d) => {
  for (final b in d.blocks.values) b.id: {'type': b.type.wire, ...b.cfg.unlock},
};

/// `edges` of [d]'s definition: `[<node>.<port>, <node>.<port>]` each.
List<List<String>> edgesJsonOf(FlowDraft d) => [
  for (final e in d.edges) [e.source.wire, e.target.wire],
];

/// `layout` of [d]'s definition: each block's place, then its pins. With
/// [placed], only those blocks have a place (the others had none when
/// read, and are written back without one).
Map<String, List<int>> layoutJsonOf(FlowDraft d, {ISet<String>? placed}) => {
  for (final b in d.blocks.values)
    if (placed?.contains(b.id) ?? true) b.id: [b.x.round(), b.y.round()],
  for (final b in d.blocks.values)
    for (final p in b.pins.entries)
      '${b.id}$_pinMark${p.key}': [if (p.value) 1 else 0, 0],
};

// ---------- pins in the layout (flow-editor.md §12) ----------

/// What stands between a node id and a field key in a pin's layout key. A
/// node id is a key segment (letters, digits, `_`, `-`, `.`), so no node
/// is named like a pin.
///
/// The `layout` key of the pin of field `f` of block `n` is
/// `<n>~pin~<f.key>` (`scale1~pin~p:k`). Its value is `[1, 0]` (pinned to
/// the block) or `[0, 0]` (taken off it); the second number is not used.
/// The engine reads `layout` as `{<key>: [x, y]}` of two finite numbers and
/// does not look at the keys (spec 06 0.2.5), so a pin travels with the
/// definition like a position does, on any broker.
const _pinMark = '~pin~';

/// The `layout` key of the pin of [field] of block [node].
String pinKey(String node, FieldId field) => '$node$_pinMark${field.key}';
