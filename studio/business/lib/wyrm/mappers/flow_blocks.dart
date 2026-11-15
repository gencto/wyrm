import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/flow_frame.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/port_end.dart';
import 'package:models/port_side.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../decode/block_cfg.dart';
import '../decode/block_def.dart';
import '../decode/flow_def.dart';
import '../decode/flow_rows.dart';
import 'flow_canvas.dart';
import 'flow_mapper.dart';

export '../decode/block_def.dart'
    show BlockPort, libraryDefOf, withLibraryVersion;

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

/// `flowEditor.libraryOff` until the library has answered.
const libraryUnread = 'unread';

/// The capabilities of a broker whose catalog is [types]. [libraryOff] is
/// why its library does not answer (`flowEditor.libraryOff`); null: it did.
FlowCaps flowCapsOf(Iterable<NodeType> types, {String? libraryOff}) => FlowCaps(
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

/// The parameter that holds the scope of a type's key field (`key_scope`,
/// `path_scope`) and the key parameter itself, by the catalog; null when
/// its type has none (an older broker, another type).
({String key, String scope, String port})? scopedKeyOf(NodeType? t) {
  for (final p in t?.params ?? const IListConst<ParamSpec>([])) {
    final port = p.port;
    if (p.scope != null && port != null) {
      return (key: p.name, scope: p.scope!, port: port);
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
      switch (b.cfg[keyed.scope]) {
        final String s => s.trim().isEmpty,
        _ => true,
      };
}

// ---------- a point or an action of the tree as a block (§18) ----------

/// The block a palette entry of the Tree tab becomes.
final class EntryBlock {
  const EntryBlock(this.type, this.cfg, {this.pins = const {}});

  final KnownBlock type;
  final Map<String, Object?> cfg;

  /// Fields taken off the block at once (an action's optional arguments).
  final Map<String, bool> pins;
}

/// A full key as a definition writes it, relative to the site.
String relativeKey(String key) =>
    key.startsWith('wy/') ? key.split('/').skip(2).join('/') : key;

/// The block of [entry]: `key:<point>` reads it (`subscribe`), `set:<point>`
/// writes it (`set`), `act:<node>/<action>` runs it (`invoke`, with one
/// argument per parameter of [action]: its default, else nothing yet).
/// Required arguments are rows of the block; the others stay in the
/// inspector. Null for anything else.
///
/// On a broker without argument ports ([FlowCaps.args]) an action keeps the
/// shape of before ADR 0040: it runs on a rising `in`, and only arguments
/// with a default are written (an empty one would be sent).
EntryBlock? blockOfEntry(
  String entry, {
  ActionInfo? action,
  FlowCaps caps = const FlowCaps(),
}) {
  if (entry.startsWith('key:')) {
    return EntryBlock(KnownBlock.subscribe, {
      'key': relativeKey(entry.substring(4)),
    });
  }
  if (entry.startsWith('set:')) {
    return EntryBlock(KnownBlock.set, {
      'path': relativeKey(entry.substring(4)),
    });
  }
  if (!entry.startsWith('act:')) {
    return null;
  }
  final full = entry.substring(4);
  final i = full.lastIndexOf('/');
  if (i <= 0) {
    return null;
  }
  final node = full.substring(0, i);
  final name = full.substring(i + 1);
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
        if (!p.required) 'arg:${p.name}': false,
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

/// The custom blocks of [d]'s definition, by name, as the definition
/// writes them (`blocks`, JSON: decode/block_def.dart reads them).
Map<String, Map<String, Object?>> blockDefsOf(FlowDraft? d) =>
    d == null ? const {} : blockDefsIn(d.rest);

/// [d] with [defs] as its `blocks` (none: the key goes).
FlowDraft withBlockDefs(FlowDraft d, Map<String, Map<String, Object?>> defs) =>
    d.copyWith(
      rest: defs.isEmpty ? d.rest.remove('blocks') : d.rest.add('blocks', defs),
    );

/// The declared inputs of a block definition, in their order.
List<BlockPort> blockInputsOf(Map<String, Object?> def, {String name = ''}) =>
    blockDefOrWarn(name, def)?.inputs ?? const [];

/// The declared outputs of a block definition, in their order.
List<BlockPort> blockOutputsOf(Map<String, Object?> def, {String name = ''}) =>
    blockDefOrWarn(name, def)?.outputs ?? const [];

/// The catalog entry the editor draws an instance of block [name] with:
/// its inputs are fields with both ports that hold a constant (`values`),
/// its outputs fields with a right port.
NodeType customTypeOf(String name, Map<String, Object?> def) {
  final read = blockDefOrWarn(name, def);
  return NodeType(
    type: CustomType(name),
    category: 'My blocks',
    description: read?.description ?? '',
    inputs: [for (final p in read?.inputs ?? const <BlockPort>[]) p.name].lock,
    outputs: [
      for (final p in read?.outputs ?? const <BlockPort>[]) p.name,
    ].lock,
    echoInputs: true,
    takesValues: true,
  );
}

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
  final name = blockNameOf(b.type);
  final def = blockDefsOf(d)[name];
  return def == null
      ? null
      : blockInputsOf(
          def,
          name: name ?? '',
        ).where((p) => p.name == port).firstOrNull?.defaultValue;
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
  final name = blockNameOf(b.type);
  final def = name == null ? null : blockDefsOf(d)[name];
  final read = def == null ? null : blockDefOrWarn(name!, def);
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
  for (final MapEntry(:key, :value) in blockDefsOf(root).entries) {
    n += blockDefOrWarn(key, value)?.instances(type) ?? 0;
  }
  return n;
}

/// The blocks [def] uses, directly: the types of its instances.
Set<String> _uses(String name, Map<String, Object?> def) =>
    blockDefOrWarn(name, def)?.uses ?? const {};

/// [names] and every block of [defs] they use, used blocks first: the
/// order a library takes them in (`put_block` refuses a block that uses one
/// it does not hold).
List<String> blockClosure(
  Map<String, Map<String, Object?>> defs,
  Iterable<String> names,
) {
  final out = <String>[];
  final seen = <String>{};
  void visit(String n) {
    final def = defs[n];
    if (def == null || !seen.add(n)) {
      return;
    }
    _uses(n, def).forEach(visit);
    out.add(n);
  }

  names.forEach(visit);
  return out;
}

/// The blocks the nodes of [d] are instances of, with all they use.
List<String> blocksUsedBy(
  FlowDraft d,
  Map<String, Map<String, Object?>> defs,
) => blockClosure(defs, [
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
  // on its left.
  final inner = FlowDraft(
    id: '',
    blocks: {
      for (final b in sub.blocks.values)
        b.id: b.copyWith(x: b.x - left + 320, y: b.y - top + 60),
    }.lock,
    edges: sub.edges,
  );
  final def = <String, Object?>{
    if (spec.description.trim().isNotEmpty)
      'description': spec.description.trim(),
    'inputs': [
      for (final (i, p) in sub.inputs.indexed)
        {
          'name': spec.inputs[i],
          'to': [for (final e in p.inside) e.wire],
          'default': ?spec.defaults[spec.inputs[i]],
        },
    ],
    'outputs': [
      for (final (i, p) in sub.outputs.indexed)
        {
          'name': spec.outputs[i],
          'from': p.inside.first.wire,
        },
    ],
    'nodes': nodesJsonOf(inner),
    'edges': edgesJsonOf(inner),
    'layout': {
      ...layoutJsonOf(inner),
      inputsAtKey: [40, 60],
      outputsAtKey: [(right - left + 320 + 300).round(), 60],
    },
  };
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
  final defs = blockDefsOf(outer);
  final def = defs[name];
  if (def == null) {
    return null;
  }
  final read = blockDefOrWarn(name, def);
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
    rest: <String, Object?>{
      'blocks': defs,
      'description': ?read.description,
    }.lock,
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
Map<String, Object?> blockDefOfInside(FlowDraft inner, {int? mark}) {
  final body = FlowDraft(
    id: inner.id,
    blocks: inner.blocks.removeWhere((id, _) => isBoundary(id)),
    edges: inner.edges.removeWhere(
      (e) => isBoundary(e.from) || isBoundary(e.to),
    ),
  );
  final ins = inner.blocks[blockInputsId];
  final outs = inner.blocks[blockOutputsId];
  final defaults = ins?.cfgDefaults ?? const <String, Object?>{};
  final notes = ins?.cfgDescriptions ?? const <String, Object?>{};
  final bounds = boundaryOf(inner);
  return {
    if (inner.rest['description'] case final String s when s.isNotEmpty)
      'description': s,
    'inputs': [
      for (final n in bounds.inputs)
        {
          'name': n,
          'to': [
            for (final e in inner.edges)
              if (e.from == blockInputsId && e.fromPort == n) e.target.wire,
          ],
          'default': ?defaults[n],
          if (notes[n] case final String s) 'description': s,
        },
    ],
    'outputs': [
      for (final n in bounds.outputs)
        {
          'name': n,
          'from': inner.edges
              .where((e) => e.to == blockOutputsId && e.toPort == n)
              .map((e) => e.source.wire)
              .firstOrNull,
          if (notes[n] case final String s) 'description': s,
        }..removeWhere((k, v) => v == null),
    ],
    'nodes': nodesJsonOf(body),
    'edges': edgesJsonOf(body),
    'layout': {
      ...layoutJsonOf(body),
      if (ins != null) inputsAtKey: [ins.x.round(), ins.y.round()],
      if (outs != null) outputsAtKey: [outs.x.round(), outs.y.round()],
      if (mark != null) libraryMarkKey: [mark, 0],
    },
  };
}

/// [outer] with what was done inside block [name]: the flow's blocks as
/// [inner] holds them now (one made or copied inside is the flow's), and
/// [name] as [inner] draws it. An instance of [name] in [outer] loses the
/// wires and the constants of a port the block no longer has.
FlowDraft foldInside(FlowDraft outer, String name, FlowDraft inner) {
  final before = blockDefsOf(outer)[name];
  final def = blockDefOfInside(
    inner,
    mark: before == null ? null : libraryVersionOf(before),
  );
  final defs = {...blockDefsOf(inner), name: def};
  final ins = {for (final p in blockInputsOf(def, name: name)) p.name};
  final outs = {for (final p in blockOutputsOf(def, name: name)) p.name};
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
        (e.key == from ? to : e.key): withInstancesRenamed(e.value, was, now),
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

/// The library version block [def] of a flow was copied at; null for a
/// block made in the flow.
int? libraryVersionOf(Map<String, Object?> def, {String name = ''}) =>
    blockDefOrWarn(name, def)?.libraryVersion;

/// [root] with library block [name] copied into its `blocks` at
/// [version], and the blocks it uses ([requires]). A flow copies, it does
/// not link (ADR 0040 §3): a block of the flow with the name of a required
/// one is kept as the flow has it; [name] itself is kept too unless
/// [replace] (`Update from library`).
FlowDraft withLibraryBlock(
  FlowDraft root,
  String name,
  Map<String, Object?> def, {
  required int version,
  Map<String, Map<String, Object?>> requires = const {},
  bool replace = false,
}) {
  final defs = {...blockDefsOf(root)};
  for (final e in requires.entries) {
    defs.putIfAbsent(e.key, () => e.value);
  }
  if (replace || !defs.containsKey(name)) {
    defs[name] = withLibraryVersion(def, version);
  }
  return withBlockDefs(root, defs);
}

/// Whether two definitions say the same block (the editor's mark aside).
bool sameBlockDef(Map<String, Object?> a, Map<String, Object?> b) =>
    Value.from(libraryDefOf(a)) == Value.from(libraryDefOf(b));
