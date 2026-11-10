import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/block_info.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/flow_frame.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'flow_canvas.dart';
import 'flow_mapper.dart';
import 'values.dart';

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
  final keyed = scopedKeyOf(types.where((t) => t.type == b.type).firstOrNull);
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

  final String type;
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
    return EntryBlock('subscribe', {'key': relativeKey(entry.substring(4))});
  }
  if (entry.startsWith('set:')) {
    return EntryBlock('set', {'path': relativeKey(entry.substring(4))});
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
    return EntryBlock('invoke', {
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
    'invoke',
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
  final m = v?.value;
  if (v == null || m is! Map || m['event'] == null && m['code'] == null) {
    return null;
  }
  final at = v.time.microsecondsSinceEpoch == 0 ? null : clockText(v.time);
  final code = m['code'];
  final message = m['message'];
  final what = [
    if (code != null) '$code',
    if (message is String && message.isNotEmpty) message,
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

/// The prefix of an instance's type: `block:<name>`.
const blockTypePrefix = 'block:';

/// The two blocks the inside of a custom block shows beside its nodes: its
/// inputs (one right port each) and its outputs (one left port each). They
/// are the editor's: a wire from `~in.<a>` to an inner input is the `to` of
/// input `a`, a wire from an inner output to `~out.<x>` the `from` of
/// output `x`.
const blockInputsId = '~in';
const blockOutputsId = '~out';
const blockInputsType = 'block~inputs';
const blockOutputsType = 'block~outputs';

/// Where the inside view keeps the two blocks' positions, and the library
/// version a block was copied at: editor keys of the block's `layout`
/// (spec 06 0.2.26: the engine reads none of it).
const _inputsAt = '_~port~in';
const _outputsAt = '_~port~out';
const _libraryMark = '_~lib~version';

/// The limits of spec 06 0.2.24.
const maxBlocks = 64;
const maxBlockPorts = 64;

final _name = RegExp(r'^[A-Za-z0-9_]+$');

/// Whether [s] may name a custom block, one of its ports or a node.
bool blockNameOk(String s) => _name.hasMatch(s);

/// Whether a node of [type] is an instance of a custom block.
bool isInstance(String type) => type.startsWith(blockTypePrefix);

/// The custom block a node of [type] is an instance of.
String? blockNameOf(String type) =>
    isInstance(type) ? type.substring(blockTypePrefix.length) : null;

/// Whether [id] is one of the two boundary blocks of an inside view.
bool isBoundary(String id) => id == blockInputsId || id == blockOutputsId;

Map<String, Object?> _map(Object? v) => switch (v) {
  final Map<Object?, Object?> m => {
    for (final e in m.entries)
      if (e.key case final String k) k: e.value,
  },
  _ => const {},
};

List<Object?> _list(Object? v) => v is List<Object?> ? v : const [];

/// The custom blocks of [d]'s definition, by name, as the definition
/// writes them (`blocks`).
Map<String, Map<String, Object?>> blockDefsOf(FlowDraft? d) => {
  for (final e in _map(d?.rest['blocks']).entries) e.key: _map(e.value),
};

/// [d] with [defs] as its `blocks` (none: the key goes).
FlowDraft withBlockDefs(FlowDraft d, Map<String, Map<String, Object?>> defs) =>
    d.copyWith(
      rest: defs.isEmpty ? d.rest.remove('blocks') : d.rest.add('blocks', defs),
    );

/// One declared input or output of a custom block.
final class BlockPort {
  const BlockPort(
    this.name, {
    this.ends = const [],
    this.defaultValue,
    this.description,
  });

  final String name;

  /// An input: the inner inputs it feeds (`to`); an output: the one inner
  /// output it sends (`from`). Each `<inner>.<port>`.
  final List<String> ends;
  final Object? defaultValue;
  final String? description;
}

/// The declared inputs of a block definition, in their order.
List<BlockPort> blockInputsOf(Map<String, Object?> def) => [
  for (final p in _list(def['inputs']))
    if (_map(p) case final m when m['name'] is String)
      BlockPort(
        m['name']! as String,
        ends: switch (m['to']) {
          final String s => [s],
          final List<Object?> l => [for (final x in l) ?(x as String?)],
          _ => const [],
        },
        defaultValue: m['default'],
        description: m['description'] as String?,
      ),
];

/// The declared outputs of a block definition, in their order.
List<BlockPort> blockOutputsOf(Map<String, Object?> def) => [
  for (final p in _list(def['outputs']))
    if (_map(p) case final m when m['name'] is String)
      BlockPort(
        m['name']! as String,
        ends: [?(m['from'] as String?)],
        description: m['description'] as String?,
      ),
];

/// The catalog entry the editor draws an instance of block [name] with:
/// its inputs are fields with both ports that hold a constant (`values`),
/// its outputs fields with a right port.
NodeType customTypeOf(String name, Map<String, Object?> def) => NodeType(
  type: '$blockTypePrefix$name',
  category: 'My blocks',
  description: def['description'] as String? ?? '',
  inputs: [for (final p in blockInputsOf(def)) p.name].lock,
  outputs: [for (final p in blockOutputsOf(def)) p.name].lock,
  echoInputs: true,
  takesValues: true,
);

/// The two boundary blocks' types: the inputs block sends one output per
/// name of its `inputs`, the outputs block takes one input per name of its
/// `outputs`.
const _boundaryTypes = [
  NodeType(
    type: blockInputsType,
    dynOutParam: 'inputs',
    echoInputs: false,
  ),
  NodeType(
    type: blockOutputsType,
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
  final def = blockDefsOf(d)[blockNameOf(b.type)];
  return def == null
      ? null
      : blockInputsOf(
          def,
        ).where((p) => p.name == port).firstOrNull?.defaultValue;
}

/// Where a field of instance [b] reads its live value: the inner input its
/// declared input feeds first (`to[0]`), or the inner output its declared
/// output sends (`from`), as `(node, port)` under the instance's id
/// (`m1/sum`). Rows of `watch`, `ports` and `preview` carry the inner nodes
/// under these ids; an instance has no row of its own.
(String, String)? instanceEnd(
  FlowDraft d,
  FlowBlock b,
  String port, {
  required bool output,
}) {
  final def = blockDefsOf(d)[blockNameOf(b.type)];
  if (def == null) {
    return null;
  }
  final ports = output ? blockOutputsOf(def) : blockInputsOf(def);
  final end = endpoint(
    ports.where((p) => p.name == port).firstOrNull?.ends.firstOrNull,
  );
  return end == null ? null : ('${b.id}/${end.$1}', end.$2);
}

/// How many instances of block [name] the flow [root] has: among its nodes
/// and inside its other blocks.
int instancesOf(FlowDraft root, String name) {
  final type = '$blockTypePrefix$name';
  var n = root.blocks.values.where((b) => b.type == type).length;
  for (final def in blockDefsOf(root).values) {
    n += _map(def['nodes']).values.where((x) => _map(x)['type'] == type).length;
  }
  return n;
}

/// The blocks [def] uses, directly: the types of its instances.
Set<String> _uses(Map<String, Object?> def) => {
  for (final n in _map(def['nodes']).values)
    if (_map(n)['type'] case final String t when isInstance(t)) blockNameOf(t)!,
};

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
    _uses(def).forEach(visit);
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
  final body = toDart(defOf(inner, 0))! as Map<String, Object?>;
  final def = <String, Object?>{
    if (spec.description.trim().isNotEmpty)
      'description': spec.description.trim(),
    'inputs': [
      for (final (i, p) in sub.inputs.indexed)
        {
          'name': spec.inputs[i],
          'to': [for (final e in p.inside) '${e.$1}.${e.$2}'],
          'default': ?spec.defaults[spec.inputs[i]],
        },
    ],
    'outputs': [
      for (final (i, p) in sub.outputs.indexed)
        {
          'name': spec.outputs[i],
          'from': '${p.inside.first.$1}.${p.inside.first.$2}',
        },
    ],
    'nodes': body['nodes'],
    'edges': body['edges'],
    'layout': {
      ..._map(body['layout']),
      _inputsAt: [40, 60],
      _outputsAt: [(right - left + 320 + 300).round(), 60],
    },
  };
  final id = freeBlockId('${spec.name}1', d.blocks.containsKey);
  final rest = withoutBlocks(d, ids);
  final next = rest.copyWith(
    blocks: rest.blocks.add(
      id,
      FlowBlock(
        id: id,
        type: '$blockTypePrefix${spec.name}',
        x: left,
        y: top,
      ),
    ),
    edges: rest.edges.addAll([
      for (final (i, p) in sub.inputs.indexed)
        FlowEdge(
          from: p.outside.first.$1,
          fromPort: p.outside.first.$2,
          to: id,
          toPort: spec.inputs[i],
        ),
      for (final (i, p) in sub.outputs.indexed)
        for (final o in p.outside)
          FlowEdge(
            from: id,
            fromPort: spec.outputs[i],
            to: o.$1,
            toPort: o.$2,
          ),
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
  final layout = _map(def['layout']);
  final d = flowDraftOf(
    outer.id,
    Value.from({
      'nodes': _map(def['nodes']),
      'edges': _list(def['edges']),
      'layout': layout,
    }),
  );
  final ins = blockInputsOf(def);
  final outs = blockOutputsOf(def);
  (double, double) at(String key, double x) => switch (layout[key]) {
    [final num a, final num b] => (a.toDouble(), b.toDouble()),
    _ => (x, 60),
  };
  final right = d.blocks.values.fold<double>(320, (m, b) => b.x > m ? b.x : m);
  final (ix, iy) = at(_inputsAt, 40);
  final (ox, oy) = at(_outputsAt, right + 300);
  return d.copyWith(
    version: outer.version,
    blocks: d.blocks
        .add(
          blockInputsId,
          FlowBlock(
            id: blockInputsId,
            type: blockInputsType,
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
            type: blockOutputsType,
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
          if (endpoint(e) case (final node, final port))
            FlowEdge(
              from: blockInputsId,
              fromPort: p.name,
              to: node,
              toPort: port,
            ),
      for (final p in outs)
        for (final e in p.ends)
          if (endpoint(e) case (final node, final port))
            FlowEdge(
              from: node,
              fromPort: port,
              to: blockOutputsId,
              toPort: p.name,
            ),
    ]),
    rest: <String, Object?>{
      'blocks': defs,
      if (def['description'] case final String s) 'description': s,
    }.lock,
  );
}

List<String> _names(Object? v) => [
  for (final x in _list(v))
    if (x is String && x.isNotEmpty) x,
];

/// The names of the inside's inputs and outputs, from its boundary blocks.
({List<String> inputs, List<String> outputs}) boundaryOf(FlowDraft inner) => (
  inputs: _names(inner.blocks[blockInputsId]?.cfg['inputs']),
  outputs: _names(inner.blocks[blockOutputsId]?.cfg['outputs']),
);

/// The definition the inside draft [inner] says: its nodes and edges
/// without the boundary blocks, an input per name of the inputs block with
/// the inner inputs its wires reach, an output per name of the outputs
/// block with the inner output wired to it. [mark] keeps the library
/// version the block was copied at.
Map<String, Object?> blockDefOfInside(FlowDraft inner, {int? mark}) {
  final body =
      toDart(
            defOf(
              FlowDraft(
                id: '',
                blocks: inner.blocks.removeWhere((id, _) => isBoundary(id)),
                edges: inner.edges.removeWhere(
                  (e) => isBoundary(e.from) || isBoundary(e.to),
                ),
              ),
              0,
            ),
          )!
          as Map<String, Object?>;
  final ins = inner.blocks[blockInputsId];
  final outs = inner.blocks[blockOutputsId];
  final defaults = _map(ins?.cfg['defaults']);
  final notes = _map(ins?.cfg['descriptions']);
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
              if (e.from == blockInputsId && e.fromPort == n)
                '${e.to}.${e.toPort}',
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
              .map((e) => '${e.from}.${e.fromPort}')
              .firstOrNull,
          if (notes[n] case final String s) 'description': s,
        }..removeWhere((k, v) => v == null),
    ],
    'nodes': body['nodes'],
    'edges': body['edges'],
    'layout': {
      ..._map(body['layout']),
      if (ins != null) _inputsAt: [ins.x.round(), ins.y.round()],
      if (outs != null) _outputsAt: [outs.x.round(), outs.y.round()],
      if (mark != null) _libraryMark: [mark, 0],
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
  final ins = {for (final p in blockInputsOf(def)) p.name};
  final outs = {for (final p in blockOutputsOf(def)) p.name};
  final type = '$blockTypePrefix$name';
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
  final key = input ? 'inputs' : 'outputs';
  final b = inner.blocks[id];
  if (b == null) {
    return null;
  }
  final names = _names(b.cfg[key]);
  if (add ? names.length >= maxBlockPorts : names.isEmpty) {
    return null;
  }
  final gone = add ? null : names.last;
  final next = add
      ? [...names, nextBoundaryName(inner, input: input)]
      : names.sublist(0, names.length - 1);
  var cfg = b.cfg.add(key, next);
  if (gone != null && input) {
    cfg = cfg.add('defaults', _map(cfg['defaults'])..remove(gone));
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
  final was = '$blockTypePrefix$from';
  final now = '$blockTypePrefix$to';
  Map<String, Object?> renamed(Map<String, Object?> def) => {
    ...def,
    'nodes': {
      for (final e in _map(def['nodes']).entries)
        e.key: switch (_map(e.value)) {
          final m when m['type'] == was => {...m, 'type': now},
          final m => m,
        },
    },
  };
  return withBlockDefs(
    root.copyWith(
      blocks: root.blocks.map(
        (id, b) => MapEntry(id, b.type == was ? b.copyWith(type: now) : b),
      ),
    ),
    {
      for (final e in defs.entries)
        (e.key == from ? to : e.key): renamed(e.value),
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

/// One row of `list_blocks`.
BlockInfo blockInfoOf(Value v) => BlockInfo(
  name: str(v['name']) ?? '',
  version: integer(v['version']) ?? 0,
  description: str(v['description']),
  inputs: [
    if (v['inputs'] case VArray(:final v))
      for (final x in v) ?str(x),
  ].lock,
  outputs: [
    if (v['outputs'] case VArray(:final v))
      for (final x in v) ?str(x),
  ].lock,
);

/// The library version block [def] of a flow was copied at; null for a
/// block made in the flow.
int? libraryVersionOf(Map<String, Object?> def) =>
    switch (_map(def['layout'])[_libraryMark]) {
      [final num v, ...] => v.toInt(),
      _ => null,
    };

/// [def] marked as copied from the library at [version].
Map<String, Object?> withLibraryVersion(
  Map<String, Object?> def,
  int version,
) => {
  ...def,
  'layout': {
    ..._map(def['layout']),
    _libraryMark: [version, 0],
  },
};

/// [def] as the library takes it: without the editor's mark of where it
/// came from.
Map<String, Object?> libraryDefOf(Map<String, Object?> def) {
  final layout = {..._map(def['layout'])}..remove(_libraryMark);
  return {...def, 'layout': layout};
}

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

/// `get_block`'s answer `{name, version, def, requires}`.
({
  int version,
  Map<String, Object?> def,
  Map<String, Map<String, Object?>> requires,
})
libraryBlockOf(Value answer) => (
  version: integer(answer['version']) ?? 0,
  def: _map(toDart(answer['def'])),
  requires: {
    for (final e in _map(toDart(answer['requires'])).entries)
      e.key: _map(e.value),
  },
);

/// Whether two definitions say the same block (the editor's mark aside).
bool sameBlockDef(Map<String, Object?> a, Map<String, Object?> b) =>
    Value.from(libraryDefOf(a)) == Value.from(libraryDefOf(b));
