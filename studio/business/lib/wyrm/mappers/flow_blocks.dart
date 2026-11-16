import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/block_def.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/flow_frame.dart';
import 'package:models/json_value.dart';
import 'package:models/library_off.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:models/param_spec.dart';
import 'package:models/port_end.dart';
import 'package:models/port_side.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../decode/block_def.dart';
import '../decode/flow_rows.dart';
import 'block_cfg.dart';
import 'flow_canvas.dart';
import 'flow_mapper.dart';

export 'package:models/block_def.dart';

// What ADR 0040 adds to the flow editor (flow-editor.md §17–§20, owner
// requirements 2026-11-09): what the broker can do (read from its catalog),
// the scope of a key that comes on a port, the block a point or an action of
// the tree becomes, and custom blocks — a definition's `blocks`, their
// instances, the inside of one as a draft of its own, and the site's library.
// All pure: the actions of `redux/flow_editor` store what these return.

// ---------- what the broker can do ----------

/// What the flow engine of the site can do beyond ADR 0038, read from its
/// catalog and from the library's answer. A broker without ADR 0040 has
/// none: the editor then says why a thing is off, and nothing breaks.
final class FlowCaps {
  const FlowCaps({
    this.scopes = false,
    this.trigger = false,
    this.args = false,
    this.blocks = false,
  });

  /// A key may come on a port inside a scope (`params[].scope`).
  final bool scopes;

  /// `dataflows/<id>` ▸ `trigger {node}` (a type with `trigger: true`).
  final bool trigger;

  /// An `invoke` argument is a field with a port (`dyn_inputs.keys`).
  final bool args;

  /// Custom blocks and their library (`list_blocks` answered).
  final bool blocks;

  @override
  bool operator ==(Object other) =>
      other is FlowCaps &&
      other.scopes == scopes &&
      other.trigger == trigger &&
      other.args == args &&
      other.blocks == blocks;

  @override
  int get hashCode => Object.hash(scopes, trigger, args, blocks);

  @override
  String toString() =>
      'FlowCaps(scopes: $scopes, trigger: $trigger, args: $args, '
      'blocks: $blocks)';
}

/// The capabilities of a broker whose catalog is [types]. [libraryOff] is
/// why its library does not answer (`flowEditor.libraryOff`); null: it did.
FlowCaps flowCapsOf(Iterable<NodeType> types, {LibraryOff? libraryOff}) =>
    FlowCaps(
      scopes: types.any((t) => t.params.any((p) => p.scope != null)),
      trigger: types.any((t) => t.trigger),
      args: types.any((t) => t.dynInKeys),
      blocks: libraryOff == null,
    );

// ---------- the scope of a key from a port (ADR 0040 §1) ----------

/// The sections of a site a flow may read (spec 06 step 9).
const scopeSections = ['downstream', 'dataflows', 'storage'];

/// What is wrong with a scope.
enum ScopeProblem {
  /// Nothing typed.
  empty,

  /// It does not start with `downstream`, `dataflows` or `storage` of this
  /// site as a literal segment.
  section,

  /// A full key of another site.
  otherSite,

  /// A segment that is no key segment and no wildcard.
  segment,
}

/// The scope the editor proposes when [key] gets a wire: the key's parent
/// and everything below it (`downstream/modbus/line1/**`); with no key, or
/// a key right under a section, the whole section.
String scopeSuggestion(String? key, {String site = ''}) {
  final rel = _relative(key ?? '', site) ?? '';
  final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty || !scopeSections.contains(parts.first)) {
    return '${scopeSections.first}/**';
  }
  if (parts.length <= 2) {
    return '${parts.first}/**';
  }
  return '${parts.take(parts.length - 1).join('/')}/**';
}

/// [key] relative to `wy/<site>/`; null when it is a full key of another
/// site.
String? _relative(String key, String site) {
  if (!key.startsWith('wy/')) {
    return key;
  }
  final prefix = 'wy/$site/';
  return site.isNotEmpty && key.startsWith(prefix)
      ? key.substring(prefix.length)
      : null;
}

final _segment = RegExp(r'^[A-Za-z0-9_.\-]+$');

/// What is wrong with [scope] as a `key_scope` of a flow of [site]; null
/// when the engine takes it: a key expression, relative to `wy/<site>/` or
/// full, whose first segment is `downstream`, `dataflows` or `storage`
/// written out (no wildcard of it can reach `sys` or another site), and
/// whose other segments are key segments, `*` or `**`.
ScopeProblem? scopeProblem(String scope, {required String site}) {
  final s = scope.trim();
  if (s.isEmpty) {
    return ScopeProblem.empty;
  }
  final rel = _relative(s, site);
  if (rel == null) {
    return ScopeProblem.otherSite;
  }
  final parts = rel.split('/');
  if (!scopeSections.contains(parts.first)) {
    return ScopeProblem.section;
  }
  for (final p in parts.skip(1)) {
    if (p != '*' && p != '**' && !_segment.hasMatch(p)) {
      return ScopeProblem.segment;
    }
  }
  return null;
}

/// A key parameter that may come on a port, and the parameter that holds
/// its scope (ADR 0040 §1), by the catalog.
final class ScopedKey {
  const ScopedKey({required this.key, required this.scope, required this.port});

  /// The key parameter (`key`, `path`).
  final String key;

  /// The parameter that holds its scope (`key_scope`, `path_scope`).
  final String scope;

  /// The input a key comes on (`in.key`).
  final String port;

  /// The key's field.
  FieldId get keyField => FieldId.param(key);

  /// The scope's field.
  FieldId get scopeField => FieldId.param(scope);

  @override
  bool operator ==(Object other) =>
      other is ScopedKey &&
      other.key == key &&
      other.scope == scope &&
      other.port == port;

  @override
  int get hashCode => Object.hash(key, scope, port);

  @override
  String toString() => 'ScopedKey($key, $scope, $port)';
}

/// The scoped key of a type ([ScopedKey]); null when its type has none
/// (an older broker, another type).
ScopedKey? scopedKeyOf(NodeType? t) {
  for (final p in t?.params ?? const IListConst<ParamSpec>([])) {
    final port = p.port;
    final scope = p.scope;
    if (scope != null && port != null) {
      return ScopedKey(key: p.name, scope: scope, port: port);
    }
  }
  return null;
}

/// Whether a wire into `<to>.<toPort>` of [d] makes the editor ask for a
/// scope: the port is a key's and the block has no scope yet (the engine
/// refuses the definition: `key_scope: required when in.key is wired`).
bool scopeAsked(
  Iterable<NodeType> types,
  FlowDraft d,
  String to,
  String toPort,
) {
  final b = d.blocks[to];
  if (b == null) {
    return false;
  }
  final keyed = scopedKeyOf(
    types.where((t) => t.type == b.type).firstOrNull,
  );
  return keyed != null &&
      keyed.port == toPort &&
      (b.textOf(keyed.scope)?.trim().isEmpty ?? true);
}

// ---------- a point or an action of the tree as a block (§18) ----------

/// The block a palette entry of the Tree tab becomes.
final class EntryBlock {
  const EntryBlock(this.type, this.cfg, {this.pins = const {}});

  final KnownBlock type;
  final Map<String, Object?> cfg;

  /// Fields taken off the block at once (an action's optional arguments).
  final Map<FieldId, bool> pins;
}

/// A full key as a definition writes it, relative to the site.
String relativeKey(String key) =>
    key.startsWith('wy/') ? key.split('/').skip(2).join('/') : key;

/// A point key of a definition (relative to the site, or full) as a full
/// key under [root] (`wy/<site>`).
String fullKey(String root, String key) =>
    key.startsWith('wy/') ? key : '$root/$key';

/// What a block's header says of the point [key] it names: the key
/// without `wy/<site>/` and `downstream/` (`modbus/tank/level`), its
/// parent's for a point of a node ([parent]: `modbus/tank`); empty for
/// none.
String connectionOf(String? key, {required bool parent}) {
  if (key == null) {
    return '';
  }
  var parts = key.split('/');
  if (parts.first == 'wy' && parts.length > 2) {
    parts = parts.skip(2).toList();
  }
  if (parts.first == scopeSections.first) {
    parts = parts.skip(1).toList();
  }
  if (parent && parts.length > 1) {
    parts = parts.take(parts.length - 1).toList();
  }
  return parts.join('/');
}

/// The block of [entry]: a point reads it (`subscribe`), or writes it
/// (`set`) when dropped as [write]; an action runs it (`invoke`, with one
/// argument per parameter of [action]: its default, else nothing yet).
/// Required arguments are rows of the block; the others stay in the
/// inspector. Null for a type or a library block (they are placed as they
/// are).
///
/// On a broker without argument ports ([FlowCaps.args]) an action keeps the
/// shape of before ADR 0040: it runs on a rising `in`, and only arguments
/// with a default are written (an empty one would be sent).
EntryBlock? blockOfEntry(
  PaletteEntry entry, {
  bool write = false,
  ActionInfo? action,
  FlowCaps caps = const FlowCaps(),
}) {
  if (entry is PointPick) {
    return write
        ? EntryBlock(KnownBlock.set, {
            BlockCfgKey.path.wire: relativeKey(entry.key),
          })
        : EntryBlock(KnownBlock.subscribe, {
            BlockCfgKey.key.wire: relativeKey(entry.key),
          });
  }
  if (entry is! ActionPick) {
    return null;
  }
  final node = entry.node;
  final name = entry.action;
  final params = action?.params ?? const IListConst<ParamSpec>([]);
  if (!caps.args) {
    return EntryBlock(KnownBlock.invoke, {
      'path': relativeKey(node),
      'action': name,
      'on': 'rising',
      if (params.any((p) => p.defaultValue != null))
        'args': {
          for (final p in params) p.name: ?p.defaultValue,
        },
    });
  }
  return EntryBlock(
    KnownBlock.invoke,
    {
      'path': relativeKey(node),
      'action': name,
      if (params.isNotEmpty)
        'args': {for (final p in params) p.name: p.defaultValue},
    },
    pins: {
      for (final p in params)
        if (!p.required) FieldId.arg(p.name): false,
    },
  );
}

// ---------- events and times (§19) ----------

/// `14:03:27`, local time.
String clockText(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

/// What an event output (`sent`, `ok`, `error`) reads: when it last fired
/// and, for an error, its code and message (`14:03:27 · busy: queue
/// full`). Null when [v] holds no event.
String? eventText(LiveValue? v) {
  final e = flowEventOf(v?.value);
  if (v == null || e == null) {
    return null;
  }
  final at = v.time.microsecondsSinceEpoch == 0 ? null : clockText(v.time);
  final what = [
    if (e.code case final code?) '$code',
    ?e.message,
  ].join(': ');
  return [?at, if (what.isNotEmpty) what].join(' · ');
}

/// `last_run` (µs since the epoch) as a clock time; null when it is none.
String? lastRunText(Object? micros) => switch (micros) {
  final num n when n > 0 => clockText(
    DateTime.fromMicrosecondsSinceEpoch(n.toInt(), isUtc: true),
  ),
  _ => null,
};

// ---------- custom blocks in a definition (ADR 0040 §3) ----------

/// The two blocks the inside of a custom block shows beside its nodes: its
/// inputs (one right port each) and its outputs (one left port each). They
/// are the editor's: a wire from `~in.<a>` to an inner input is the `to` of
/// input `a`, a wire from an inner output to `~out.<x>` the `from` of
/// output `x`.
const blockInputsId = '~in';
const blockOutputsId = '~out';

/// The limits of spec 06 0.2.24.
const maxBlocks = 64;
const maxBlockPorts = 64;

final _name = RegExp(r'^[A-Za-z0-9_]+$');

/// Whether [s] may name a custom block, one of its ports or a node.
bool blockNameOk(String s) => _name.hasMatch(s);

/// Whether a node of [type] is an instance of a custom block.
bool isInstance(BlockType type) => type is CustomType;

/// The custom block a node of [type] is an instance of.
String? blockNameOf(BlockType? type) => switch (type) {
  CustomType(:final name) => name,
  _ => null,
};

/// Whether [id] is one of the two boundary blocks of an inside view.
bool isBoundary(String id) => id == blockInputsId || id == blockOutputsId;

/// The custom blocks of [d]'s definition, by name ([FlowDraft.defs]).
Map<String, BlockDef> blockDefsOf(FlowDraft? d) =>
    d == null ? const {} : d.defs.unlock;

/// [d] with [defs] as its custom blocks.
FlowDraft withBlockDefs(FlowDraft d, Map<String, BlockDef> defs) =>
    d.copyWith(defs: defs.lock);

/// The catalog entry the editor draws an instance of block [name] with:
/// its inputs are fields with both ports that hold a constant (`values`),
/// its outputs fields with a right port.
NodeType customTypeOf(String name, BlockDef def) => NodeType(
  type: CustomType(name),
  category: 'My blocks',
  description: def.description ?? '',
  inputs: [for (final p in def.inputs) p.name].lock,
  outputs: [for (final p in def.outputs) p.name].lock,
  echoInputs: true,
  takesValues: true,
);

/// The two boundary blocks' types: the inputs block sends one output per
/// name of its `inputs`, the outputs block takes one input per name of its
/// `outputs`.
const _boundaryTypes = [
  NodeType(
    type: BoundaryType.inputs,
    dynOutParam: 'inputs',
    echoInputs: false,
  ),
  NodeType(
    type: BoundaryType.outputs,
    dynInParam: 'outputs',
    echoInputs: false,
  ),
];

/// The catalog [types] with one entry per custom block of [d] and, for the
/// inside of a block, its two boundary blocks.
IList<NodeType> typesWithBlocks(IList<NodeType> types, FlowDraft? d) {
  final defs = blockDefsOf(d);
  final inside = d != null && d.blocks.containsKey(blockInputsId);
  if (defs.isEmpty && !inside) {
    return types;
  }
  return types.addAll([
    for (final e in defs.entries) customTypeOf(e.key, e.value),
    if (inside) ..._boundaryTypes,
  ]);
}

/// The constant an unbound input [port] of instance [b] holds: its own
/// `values.<input>`, else the block's `default`.
Object? instanceValueOf(FlowDraft d, FlowBlock b, String port) {
  final own = operandValueOf(b, port);
  if (own != null) {
    return own;
  }
  final def = switch (blockNameOf(b.type)) {
    final name? => d.defs[name],
    null => null,
  };
  return def?.inputs.where((p) => p.name == port).firstOrNull?.defaultValue;
}

/// Where a field of instance [b] reads its live value: the inner input its
/// declared input feeds first (`to[0]`), or the inner output its declared
/// output sends (`from`), under the instance's id (`m1/sum`). Rows of
/// `watch`, `ports` and `preview` carry the inner nodes under these ids; an
/// instance has no row of its own.
PortEnd? instanceEnd(
  FlowDraft d,
  FlowBlock b,
  String port, {
  required bool output,
}) {
  final read = switch (blockNameOf(b.type)) {
    final name? => d.defs[name],
    null => null,
  };
  if (read == null) {
    return null;
  }
  final ports = output ? read.outputs : read.inputs;
  final end = ports.where((p) => p.name == port).firstOrNull?.ends.firstOrNull;
  return end == null ? null : PortEnd('${b.id}/${end.block}', end.port);
}

/// The key in the engine's rows of the live value [key] ([portKey]) of
/// block [b], which runs as node [eid]: the block's own node, or, for an
/// instance of a custom block, the inner node its port stands for (an
/// input: the first inner input it feeds, as its echo too). Null when the
/// instance has no such port.
String? engineKeyOf(FlowDraft? d, FlowBlock b, String eid, String key) {
  final (side, port) = switch (sideOfKey(key, b.id)) {
    final at? => at,
    null => (PortSide.param, key),
  };
  if (d == null || b.type is! CustomType) {
    return portKey(side, eid, port);
  }
  final up = eid.substring(0, eid.length - b.id.length);
  final out = side == PortSide.output
      ? instanceEnd(d, b, port, output: true)
      : null;
  final end = out ?? instanceEnd(d, b, port, output: false);
  return end == null
      ? null
      : portKey(
          out != null ? PortSide.output : PortSide.input,
          '$up${end.block}',
          end.port,
        );
}

/// How many instances of block [name] the flow [root] has: among its nodes
/// and inside its other blocks.
int instancesOf(FlowDraft root, String name) {
  final type = CustomType(name);
  var n = root.blocks.values.where((b) => b.type == type).length;
  for (final def in root.defs.values) {
    n += def.instances(type);
  }
  return n;
}

/// [names] and every block of [defs] they use, used blocks first: the
/// order a library takes them in (`put_block` refuses a block that uses one
/// it does not hold).
List<String> blockClosure(Map<String, BlockDef> defs, Iterable<String> names) {
  final out = <String>[];
  final seen = <String>{};
  void visit(String n) {
    final def = defs[n];
    if (def == null || !seen.add(n)) {
      return;
    }
    def.uses.forEach(visit);
    out.add(n);
  }

  names.forEach(visit);
  return out;
}

/// The blocks the nodes of [d] are instances of, with all they use.
List<String> blocksUsedBy(FlowDraft d, Map<String, BlockDef> defs) =>
    blockClosure(defs, [
      for (final b in d.blocks.values) ?blockNameOf(b.type),
    ]);

// ---------- create a custom block from a selection (§20) ----------

/// What the Create dialog asks: the block's name and description, and for
/// each port of the selection ([extractSubflow], in its order) the name it
/// gets; an input may carry a default.
final class CustomBlockSpec {
  const CustomBlockSpec({
    required this.name,
    this.description = '',
    this.inputs = const [],
    this.outputs = const [],
    this.defaults = const {},
  });

  final String name;
  final String description;

  /// The inputs' names, in the order of [Subflow.inputs].
  final List<String> inputs;

  /// The outputs' names, in the order of [Subflow.outputs].
  final List<String> outputs;

  /// An input's default, by its name.
  final Map<String, Object?> defaults;
}

/// Why a block cannot be created or renamed.
enum BlockNameProblem {
  /// Not `[A-Za-z0-9_]+`.
  name,

  /// The flow has a block of this name.
  taken,

  /// A port's name is not `[A-Za-z0-9_]+`.
  port,

  /// Two ports read alike (inputs and outputs share one space of names).
  duplicate,

  /// 64 blocks already, or more than 64 inputs or outputs.
  limit,
}

/// What is wrong with [spec] for a new block of [d]; null: it can be made.
BlockNameProblem? customBlockProblem(FlowDraft d, CustomBlockSpec spec) {
  final defs = blockDefsOf(d);
  if (!blockNameOk(spec.name)) {
    return BlockNameProblem.name;
  }
  if (defs.containsKey(spec.name)) {
    return BlockNameProblem.taken;
  }
  final ports = [...spec.inputs, ...spec.outputs];
  if (!ports.every(blockNameOk)) {
    return BlockNameProblem.port;
  }
  if (ports.toSet().length != ports.length) {
    return BlockNameProblem.duplicate;
  }
  if (defs.length >= maxBlocks ||
      spec.inputs.length > maxBlockPorts ||
      spec.outputs.length > maxBlockPorts) {
    return BlockNameProblem.limit;
  }
  return null;
}

/// [d] with the blocks [ids] made one custom block [spec] and replaced by
/// one instance of it, and the instance's id. The selection's nodes and the
/// edges among them become the block's inside; an edge that crossed the
/// boundary now ends at the instance's port of that name. Null when the
/// selection is empty or [spec] is refused ([customBlockProblem]).
(FlowDraft, String)? createCustomBlock(
  FlowDraft d,
  Set<String> ids,
  CustomBlockSpec spec,
) {
  final sub = extractSubflow(d, ids);
  if (sub.blocks.isEmpty ||
      customBlockProblem(d, spec) != null ||
      spec.inputs.length != sub.inputs.length ||
      spec.outputs.length != sub.outputs.length) {
    return null;
  }
  final left = sub.blocks.values
      .map((b) => b.x)
      .reduce((a, b) => a < b ? a : b);
  final top = sub.blocks.values.map((b) => b.y).reduce((a, b) => a < b ? a : b);
  final right = sub.blocks.values
      .map((b) => b.x)
      .reduce((a, b) => a > b ? a : b);
  // The inside keeps the selection's shape, with room for the inputs block
  // on its left. Only its nodes, edges and layout are kept: the
  // definition of a block has no id.
  final inner = FlowDraft(
    id: d.id,
    blocks: {
      for (final b in sub.blocks.values)
        b.id: b.copyWith(
          x: (b.x - left + 320).roundToDouble(),
          y: (b.y - top + 60).roundToDouble(),
        ),
    }.lock,
    edges: sub.edges,
  );
  final def = BlockDef(
    body: blockBodyOf(inner.blocks, inner.edges),
    description: spec.description.trim().isEmpty
        ? null
        : spec.description.trim(),
    inputs: [
      for (final (i, p) in sub.inputs.indexed)
        BlockPort(
          spec.inputs[i],
          ends: p.inside,
          defaultValue: spec.defaults[spec.inputs[i]],
        ),
    ],
    outputs: [
      for (final (i, p) in sub.outputs.indexed)
        BlockPort(spec.outputs[i], ends: [p.inside.first]),
    ],
    inputsAt: (40, 60),
    outputsAt: ((right - left + 320 + 300).roundToDouble(), 60),
  );
  final id = freeBlockId('${spec.name}1', d.blocks.containsKey);
  final rest = withoutBlocks(d, ids);
  final next = rest.copyWith(
    blocks: rest.blocks.add(
      id,
      FlowBlock(
        id: id,
        type: CustomType(spec.name),
        x: left,
        y: top,
      ),
    ),
    edges: rest.edges.addAll([
      for (final (i, p) in sub.inputs.indexed)
        FlowEdge.between(p.outside.first, PortEnd(id, spec.inputs[i])),
      for (final (i, p) in sub.outputs.indexed)
        for (final o in p.outside)
          FlowEdge.between(PortEnd(id, spec.outputs[i]), o),
    ]),
  );
  return (withBlockDefs(next, {...blockDefsOf(d), spec.name: def}), id);
}

// ---------- the inside of a custom block as a draft (§20) ----------

/// The inside of block [name] of [outer] as a draft the canvas edits: the
/// block's nodes and edges, the two boundary blocks with a wire per `to`
/// and `from`, and every block of the flow in `rest` (so the instances the
/// block holds draw, and a block made inside lands in the flow). Null when
/// [outer] has no such block.
FlowDraft? insideDraftOf(FlowDraft outer, String name) {
  final read = outer.defs[name];
  if (read == null) {
    return null;
  }
  final d = read.body.copyWith(id: outer.id);
  final ins = read.inputs;
  final outs = read.outputs;
  final right = d.blocks.values.fold<double>(320, (m, b) => b.x > m ? b.x : m);
  final (ix, iy) = read.inputsAt ?? (40.0, 60.0);
  final (ox, oy) = read.outputsAt ?? (right + 300, 60.0);
  return d.copyWith(
    version: outer.version,
    blocks: d.blocks
        .add(
          blockInputsId,
          FlowBlock(
            id: blockInputsId,
            type: BoundaryType.inputs,
            x: ix,
            y: iy,
            cfg: <String, Object?>{
              'inputs': [for (final p in ins) p.name],
              'defaults': {
                for (final p in ins)
                  if (p.defaultValue != null) p.name: p.defaultValue,
              },
              'descriptions': {
                for (final p in [...ins, ...outs])
                  if (p.description != null) p.name: p.description,
              },
            }.lock,
          ),
        )
        .add(
          blockOutputsId,
          FlowBlock(
            id: blockOutputsId,
            type: BoundaryType.outputs,
            x: ox,
            y: oy,
            cfg: <String, Object?>{
              'outputs': [for (final p in outs) p.name],
            }.lock,
          ),
        ),
    edges: d.edges.addAll([
      for (final p in ins)
        for (final e in p.ends)
          FlowEdge.between(PortEnd(blockInputsId, p.name), e),
      for (final p in outs)
        for (final e in p.ends)
          FlowEdge.between(e, PortEnd(blockOutputsId, p.name)),
    ]),
    rest: <String, Object?>{'description': ?read.description}.lock,
    defs: outer.defs,
  );
}

/// The names of the inside's inputs and outputs, from its boundary blocks.
({List<String> inputs, List<String> outputs}) boundaryOf(FlowDraft inner) => (
  inputs:
      inner.blocks[blockInputsId]?.namesOf(BlockCfgKey.inputs.wire) ?? const [],
  outputs:
      inner.blocks[blockOutputsId]?.namesOf(BlockCfgKey.outputs.wire) ??
      const [],
);

/// The definition the inside draft [inner] says: its nodes and edges
/// without the boundary blocks, an input per name of the inputs block with
/// the inner inputs its wires reach, an output per name of the outputs
/// block with the inner output wired to it. [mark] keeps the library
/// version the block was copied at.
BlockDef blockDefOfInside(FlowDraft inner, {int? mark}) {
  final body = blockBodyOf(
    inner.blocks.removeWhere((id, _) => isBoundary(id)),
    inner.edges.removeWhere((e) => isBoundary(e.from) || isBoundary(e.to)),
  );
  final ins = inner.blocks[blockInputsId];
  final outs = inner.blocks[blockOutputsId];
  final defaults = ins?.cfgDefaults ?? const <String, Object?>{};
  final notes = ins?.cfgDescriptions ?? const <String, Object?>{};
  final bounds = boundaryOf(inner);
  String? note(String n) => switch (JsonValue.of(notes[n])) {
    JsonText(:final text) => text,
    _ => null,
  };
  return BlockDef(
    body: body,
    description: switch (JsonValue.of(inner.rest['description'])) {
      JsonText(:final text) when text.isNotEmpty => text,
      _ => null,
    },
    inputs: [
      for (final n in bounds.inputs)
        BlockPort(
          n,
          ends: [
            for (final e in inner.edges)
              if (e.from == blockInputsId && e.fromPort == n) e.target,
          ],
          defaultValue: defaults[n],
          description: note(n),
        ),
    ],
    outputs: [
      for (final n in bounds.outputs)
        BlockPort(
          n,
          ends: [
            ?inner.edges
                .where((e) => e.to == blockOutputsId && e.toPort == n)
                .map((e) => e.source)
                .firstOrNull,
          ],
          description: note(n),
        ),
    ],
    inputsAt: ins == null
        ? null
        : (ins.x.roundToDouble(), ins.y.roundToDouble()),
    outputsAt: outs == null
        ? null
        : (outs.x.roundToDouble(), outs.y.roundToDouble()),
    libraryVersion: mark,
  );
}

/// [outer] with what was done inside block [name]: the flow's blocks as
/// [inner] holds them now (one made or copied inside is the flow's), and
/// [name] as [inner] draws it. An instance of [name] in [outer] loses the
/// wires and the constants of a port the block no longer has.
FlowDraft foldInside(FlowDraft outer, String name, FlowDraft inner) {
  final def = blockDefOfInside(
    inner,
    mark: outer.defs[name]?.libraryVersion,
  );
  final defs = {...blockDefsOf(inner), name: def};
  final ins = {for (final p in def.inputs) p.name};
  final outs = {for (final p in def.outputs) p.name};
  final type = CustomType(name);
  bool mine(String id) => outer.blocks[id]?.type == type;
  return withBlockDefs(
    outer.copyWith(
      blocks: outer.blocks.map(
        (id, b) => MapEntry(
          id,
          b.type == type
              ? b.copyWith(
                  cfg: cfgWithoutOperands(
                    b.cfg,
                    operandValuesOf(
                      b,
                    ).keys.where((k) => !ins.contains(k)).toList(),
                  ),
                )
              : b,
        ),
      ),
      edges: outer.edges.removeWhere(
        (e) =>
            (mine(e.to) && !ins.contains(e.toPort)) ||
            (mine(e.from) &&
                !outs.contains(e.fromPort) &&
                !ins.contains(e.fromPort)),
      ),
    ),
    defs,
  );
}

/// The flow's own draft: [draft] when the canvas shows the flow, else the
/// flow with every inside view folded back into it ([frames], outermost
/// first). What validate, preview and deploy read.
FlowDraft? rootDraft(IList<FlowFrame> frames, FlowDraft? draft) {
  if (draft == null) {
    return null;
  }
  var d = draft;
  for (final f in frames.reversed) {
    d = foldInside(f.draft, f.block, d);
  }
  return d;
}

/// The path of instance ids from the flow to the nodes the canvas shows
/// (`m1`, `m1/k`); null when a frame was opened without an instance (from
/// the palette): its nodes have no live values.
String? insidePath(IList<FlowFrame> frames) {
  final parts = <String>[];
  for (final f in frames) {
    final i = f.instance;
    if (i == null) {
      return null;
    }
    parts.add(i);
  }
  return parts.join('/');
}

/// The id the engine knows block [id] of the canvas by: its own in the
/// flow, `<instance>/<inner>` inside a custom block ([frames]). Null
/// inside a block opened from the palette: no instance, so no running
/// node.
String? engineIdOf(IList<FlowFrame> frames, String id) {
  final path = insidePath(frames);
  return path == null ? null : (path.isEmpty ? id : '$path/$id');
}

/// The names + adds to a boundary block: `in1`, `in2`, … or `out1`, …,
/// free among the block's inputs and outputs together.
String nextBoundaryName(FlowDraft inner, {required bool input}) {
  final b = boundaryOf(inner);
  final taken = {...b.inputs, ...b.outputs};
  final base = input ? 'in' : 'out';
  var n = 1;
  while (taken.contains('$base$n')) {
    n++;
  }
  return '$base$n';
}

/// The inside draft [inner] with one more input or output ([add]), or
/// without its last one and the wires of it; null when nothing changes.
FlowDraft? resizeBoundary(
  FlowDraft inner, {
  required bool input,
  required bool add,
}) {
  final id = input ? blockInputsId : blockOutputsId;
  final key = (input ? BlockCfgKey.inputs : BlockCfgKey.outputs).wire;
  final b = inner.blocks[id];
  if (b == null) {
    return null;
  }
  final names = b.namesOf(key) ?? const <String>[];
  if (add ? names.length >= maxBlockPorts : names.isEmpty) {
    return null;
  }
  final gone = add ? null : names.last;
  final next = add
      ? [...names, nextBoundaryName(inner, input: input)]
      : names.sublist(0, names.length - 1);
  var cfg = b.cfg.add(key, next);
  if (gone != null && input) {
    cfg = cfg.add(
      BlockCfgKey.defaults.wire,
      {...b.cfgDefaults}..remove(gone),
    );
  }
  return inner.copyWith(
    blocks: inner.blocks.add(id, b.copyWith(cfg: cfg)),
    edges: gone == null
        ? inner.edges
        : inner.edges.removeWhere(
            (e) =>
                (e.from == id && e.fromPort == gone) ||
                (e.to == id && e.toPort == gone),
          ),
  );
}

// ---------- rename, delete (§20) ----------

/// [root] with block [from] named [to]: its definition, and every instance
/// of it among the flow's nodes and inside its other blocks. Null when
/// [to] is no name, or taken.
FlowDraft? renameBlock(FlowDraft root, String from, String to) {
  final defs = blockDefsOf(root);
  if (!defs.containsKey(from) || !blockNameOk(to) || defs.containsKey(to)) {
    return null;
  }
  final was = CustomType(from);
  final now = CustomType(to);
  return withBlockDefs(
    root.copyWith(
      blocks: root.blocks.map(
        (id, b) => MapEntry(id, b.type == was ? b.copyWith(type: now) : b),
      ),
    ),
    {
      for (final e in defs.entries)
        (e.key == from ? to : e.key): e.value.copyWith(
          body: e.value.body.copyWith(
            blocks: e.value.body.blocks.map(
              (id, b) =>
                  MapEntry(id, b.type == was ? b.copyWith(type: now) : b),
            ),
          ),
        ),
    },
  );
}

/// [root] without block [name]; null while an instance of it is left
/// ([instancesOf]): a block in use is not deleted.
FlowDraft? removeBlock(FlowDraft root, String name) {
  final defs = blockDefsOf(root);
  if (!defs.containsKey(name) || instancesOf(root, name) > 0) {
    return null;
  }
  return withBlockDefs(root, {...defs}..remove(name));
}

// ---------- the site's library (§20) ----------

/// [root] with library block [name] copied into its `blocks` at
/// [version], and the blocks it uses ([requires]). A flow copies, it does
/// not link (ADR 0040 §3): a block of the flow with the name of a required
/// one is kept as the flow has it; [name] itself is kept too unless
/// [replace] (`Update from library`).
FlowDraft withLibraryBlock(
  FlowDraft root,
  String name,
  BlockDef def, {
  required int version,
  Map<String, BlockDef> requires = const {},
  bool replace = false,
}) {
  final defs = {...blockDefsOf(root)};
  for (final e in requires.entries) {
    defs.putIfAbsent(e.key, () => e.value);
  }
  if (replace || !defs.containsKey(name)) {
    defs[name] = def.copyWith(libraryVersion: version);
  }
  return withBlockDefs(root, defs);
}

/// Whether two definitions say the same block (the editor's mark aside):
/// they write the same definition.
bool sameBlockDef(BlockDef a, BlockDef b) =>
    Value.from(libraryDefJsonOf(a)) == Value.from(libraryDefJsonOf(b));

/// [def] as the library takes it: without the editor's mark of where it
/// came from.
Map<String, Object?> libraryDefJsonOf(BlockDef def) =>
    blockDefJsonOf(def.copyWith(libraryVersion: null));
