import 'dart:convert';
import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'flow_blocks.dart';
import 'flow_fields.dart';
import 'flow_mapper.dart';
import 'values.dart';

// What the canvas of the flow editor does to a draft besides wiring
// (studio/docs/design/specs/flow-editor.md §12–§15, owner decisions
// 2026-11-09): pins, the undo history, the clipboard, and the cut of a
// selection into a sub-graph. All pure: the actions of `redux/flow_editor`
// only store what these return.

// ---------- pins (§12) ----------

/// Pins [f] of [b] to the block ([pinned]) or takes it off; null when
/// nothing changes: the field is bound (a bound field always shows), or it
/// already is as asked. An entry equal to the type's default is not kept,
/// so the definition holds only what the user chose.
FlowBlock? withPin(
  FlowBlock b,
  FlowField f,
  Iterable<FlowEdge> edges, {
  required bool pinned,
}) {
  if (fieldBound(b, f, edges) || fieldPinned(b, f, edges) == pinned) {
    return null;
  }
  return b.copyWith(
    pins: pinned == f.onBlock ? b.pins.remove(f.id) : b.pins.add(f.id, pinned),
  );
}

/// [d] with every bound field pinned for good: a field that gets a wire
/// (in or out) becomes a row of its block and stays one after the wire is
/// gone (flow-editor.md §12: a wire pins its field). Called by whatever
/// adds a wire.
FlowDraft pinBound(Iterable<NodeType> types, FlowDraft d) {
  if (d.edges.isEmpty) {
    return d;
  }
  final byType = {for (final t in types) t.type: t};
  final touched = {
    for (final e in d.edges) ...[e.from, e.to],
  };
  var blocks = d.blocks;
  for (final id in touched) {
    final b = blocks[id];
    if (b == null) {
      continue;
    }
    var pins = b.pins;
    for (final f in fieldsOf(byType[b.type], b, edges: d.edges)) {
      if (!(pins[f.id] ?? f.onBlock) && fieldBound(b, f, d.edges)) {
        pins = pins.add(f.id, true);
      }
    }
    if (!identical(pins, b.pins)) {
      blocks = blocks.add(id, b.copyWith(pins: pins));
    }
  }
  return identical(blocks, d.blocks) ? d : d.copyWith(blocks: blocks);
}

// ---------- undo (§13) ----------

/// How many steps back the editor keeps.
const undoLimit = 100;

/// [undo] with [before] (the draft an edit is about to replace) on top, at
/// most [undoLimit] deep. An edit with the same [tag] as the one before it
/// ([lastTag]) is the same step — typing in one field, nudging with the
/// arrows — and adds nothing.
IList<FlowDraft> undoPush(
  IList<FlowDraft> undo,
  FlowDraft before, {
  String? tag,
  String? lastTag,
}) {
  if (tag != null && tag == lastTag && undo.isNotEmpty) {
    return undo;
  }
  final next = undo.add(before);
  return next.length > undoLimit ? next.sublist(next.length - undoLimit) : next;
}

/// The draft a step of the history brings back: [step]'s blocks, edges and
/// the rest, under the id and the version [current] has now (a deploy or a
/// new flow's name is no canvas edit and is not undone).
FlowDraft restored(FlowDraft step, FlowDraft current) =>
    step.copyWith(id: current.id, version: current.version);

// ---------- blocks: delete, copy, paste (§13) ----------

/// [d] without the blocks [ids] and every edge to or from them.
FlowDraft withoutBlocks(FlowDraft d, Set<String> ids) => d.copyWith(
  blocks: d.blocks.removeWhere((id, _) => ids.contains(id)),
  edges: d.edges.removeWhere(
    (e) => ids.contains(e.from) || ids.contains(e.to),
  ),
);

/// The clipboard format: a JSON object with this `format`, and `nodes`,
/// `edges`, `layout` as a definition writes them (spec 06), plus `blocks`:
/// the custom blocks the copied instances are of, with all they use, so an
/// instance pasted into another flow brings its definition (§20).
const clipFormat = 'wyrm-flow-blocks/1';

/// A clipboard text larger than this is not read.
const int _clipMax = 4 * 1024 * 1024;

const _noLayout = <String, Object?>{};

/// The blocks [ids] of [d] as clipboard text: their config, where they
/// are, their pins, the edges among them, and the definitions of the
/// custom blocks they are instances of. An edge to or from a block outside
/// [ids] is left out, and so are the inputs and outputs blocks of a block's
/// inside. Null when [ids] names no block.
String? clipTextOf(FlowDraft d, Set<String> ids) {
  final part = FlowDraft(
    id: '',
    blocks: d.blocks.removeWhere(
      (id, _) => !ids.contains(id) || isBoundary(id),
    ),
    edges: d.edges.removeWhere(
      (e) => !ids.contains(e.from) || !ids.contains(e.to),
    ),
  );
  if (part.blocks.isEmpty) {
    return null;
  }
  final def = toDart(defOf(part, 0))! as Map<String, Object?>;
  final defs = blockDefsOf(d);
  final used = blocksUsedBy(part, defs);
  return jsonEncode({
    'format': clipFormat,
    'nodes': def['nodes'],
    'edges': def['edges'],
    'layout': def['layout'],
    if (used.isNotEmpty) 'blocks': {for (final n in used) n: defs[n]},
  });
}

/// The blocks a clipboard [text] holds, or null when it is anything else
/// (foreign text, another format, a broken shape): pasting it does nothing.
FlowDraft? clipOf(String? text) {
  if (text == null || text.isEmpty || text.length > _clipMax) {
    return null;
  }
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?> || json['format'] != clipFormat) {
    return null;
  }
  final nodes = json['nodes'];
  if (nodes is! Map<String, Object?> ||
      nodes.isEmpty ||
      nodes.values.any((n) => n is! Map || n['type'] is! String)) {
    return null;
  }
  final Value def;
  try {
    def = Value.from({
      'nodes': nodes,
      'edges': json['edges'] is List ? json['edges'] : const <Object?>[],
      'layout': json['layout'] is Map ? json['layout'] : _noLayout,
      if (json['blocks'] case final Map<String, Object?> b) 'blocks': b,
    });
  } on Object {
    return null;
  }
  final d = flowDraftOf('', def);
  // Only edges among the blocks themselves.
  return d.copyWith(
    edges: d.edges.removeWhere(
      (e) => !d.blocks.containsKey(e.from) || !d.blocks.containsKey(e.to),
    ),
  );
}

/// An id for a pasted block: [id] when it is free, else its name with the
/// next free number (`scale1` → `scale2`, `tank` → `tank1`).
String freeBlockId(String id, bool Function(String) taken) {
  if (!taken(id)) {
    return id;
  }
  final base = id.replaceFirst(RegExp(r'\d+$'), '');
  var n = 1;
  while (taken('$base$n')) {
    n++;
  }
  return '$base$n';
}

/// [d] with the blocks of [clip] added so that the top-left corner of
/// their bounding box is at ([x], [y]) (on the 20 px grid, inside the
/// canvas), and the ids they got. Ids are made unique ([freeBlockId]); the
/// edges among the pasted blocks follow the new ids. The custom blocks the
/// clip carries are copied into [d]'s `blocks`; one whose name [d] already
/// has is not: the flow keeps its own definition.
(FlowDraft, List<String>) pasteClip(
  FlowDraft d,
  FlowDraft clip,
  double x,
  double y,
) {
  if (clip.blocks.isEmpty) {
    return (d, const []);
  }
  final left = clip.blocks.values.map((b) => b.x).reduce(math.min);
  final top = clip.blocks.values.map((b) => b.y).reduce(math.min);
  double snap(double v) => math.max(0, (v / 20).round() * 20.0);
  final ids = <String, String>{};
  var blocks = d.blocks;
  for (final b in clip.blocks.values) {
    final id = freeBlockId(b.id, blocks.containsKey);
    ids[b.id] = id;
    blocks = blocks.add(
      id,
      b.copyWith(id: id, x: snap(x + b.x - left), y: snap(y + b.y - top)),
    );
  }
  final defs = blockDefsOf(d);
  final brought = blockDefsOf(clip);
  final next = d.copyWith(
    blocks: blocks,
    edges: d.edges.addAll([
      for (final e in clip.edges)
        if (ids[e.from] != null && ids[e.to] != null)
          e.copyWith(from: ids[e.from]!, to: ids[e.to]!),
    ]),
  );
  return (
    brought.keys.every(defs.containsKey)
        ? next
        : withBlockDefs(next, {...brought, ...defs}),
    ids.values.toList(),
  );
}

// ---------- a selection as a sub-graph (§13, for custom blocks) ----------

/// One port of the block a selection would become.
final class SubflowPort {
  const SubflowPort({
    required this.name,
    required this.inside,
    required this.outside,
  });

  /// Its name on the new block: unique among the block's inputs or outputs.
  final String name;

  /// The ends inside the selection, as `(node, port)`. An input: every
  /// inside input the outside source feeds. An output: the one inside
  /// output it sends.
  final List<(String, String)> inside;

  /// The ends outside the selection. An input: the one outside output that
  /// feeds it. An output: every outside input it feeds.
  final List<(String, String)> outside;

  @override
  String toString() => 'SubflowPort($name $inside ⇄ $outside)';
}

/// A selection cut out of a draft: what a custom block would hold, and the
/// ports it would have.
final class Subflow {
  const Subflow({
    required this.blocks,
    required this.edges,
    required this.inputs,
    required this.outputs,
  });

  /// The selected blocks.
  final IMap<String, FlowBlock> blocks;

  /// The edges with both ends inside.
  final IList<FlowEdge> edges;

  /// One per outside output that feeds the selection.
  final List<SubflowPort> inputs;

  /// One per inside output that feeds a block outside.
  final List<SubflowPort> outputs;
}

/// The blocks [ids] of [d] as a sub-graph. An edge with both ends inside
/// stays inside. An edge that crosses the boundary becomes a port of the
/// new block: from outside in, an input (one per outside source, so a
/// source that feeds two inside inputs is one input); from inside out, an
/// output (one per inside source). Ports are in the order of [d]'s edges
/// and named after the inside end: the node for `in`/`out`, else the port
/// (`in.` dropped), with the node in front when two would read alike.
Subflow extractSubflow(FlowDraft d, Set<String> ids) {
  final blocks = d.blocks.removeWhere((id, _) => !ids.contains(id));
  bool inside(String id) => blocks.containsKey(id);
  final ins = <(String, String), List<(String, String)>>{};
  final outs = <(String, String), List<(String, String)>>{};
  final inner = <FlowEdge>[];
  for (final e in d.edges) {
    final a = inside(e.from);
    final b = inside(e.to);
    if (a && b) {
      inner.add(e);
    } else if (b) {
      ins.putIfAbsent((e.from, e.fromPort), () => []).add((e.to, e.toPort));
    } else if (a) {
      outs.putIfAbsent((e.from, e.fromPort), () => []).add((e.to, e.toPort));
    }
  }
  String clean(String s) => s.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
  List<String> names(Iterable<(String, String)> ends) {
    String short((String, String) end) {
      final port = end.$2.startsWith('in.') ? end.$2.substring(3) : end.$2;
      return clean(port == 'in' || port == 'out' ? end.$1 : port);
    }

    final ends0 = ends.toList();
    final plain = [for (final e in ends0) short(e)];
    final used = <String>{};
    return [
      for (final (i, e) in ends0.indexed)
        () {
          var n = plain.where((p) => p == plain[i]).length > 1
              ? clean('${e.$1}_${plain[i]}')
              : plain[i];
          final base = n;
          for (var k = 2; !used.add(n); k++) {
            n = '$base$k';
          }
          return n;
        }(),
    ];
  }

  final inNames = names(ins.values.map((t) => t.first));
  final outNames = names(outs.keys);
  return Subflow(
    blocks: blocks,
    edges: inner.lock,
    inputs: [
      for (final (i, e) in ins.entries.indexed)
        SubflowPort(name: inNames[i], inside: e.value, outside: [e.key]),
    ],
    outputs: [
      for (final (i, e) in outs.entries.indexed)
        SubflowPort(name: outNames[i], inside: [e.key], outside: e.value),
    ],
  );
}

// ---------- typing a field's value (§15: the inspector, the viewer) ----------

/// How a field's value is typed.
enum FieldEdit {
  /// One of the parameter's choices.
  choice,

  /// A bool.
  toggle,

  /// A number.
  number,

  /// A map or a list, as JSON: the text must parse.
  json,

  /// A text, kept as it is.
  text,

  /// A value read as JSON when the text parses (`2` is a number, `AHU-` a
  /// text): an operand's constant, an `invoke` argument, a `dynamic`
  /// parameter.
  any,
}

/// Why a field's value cannot be typed.
enum FieldLocked {
  /// A wire feeds it: the binding wins over a typed value.
  bound,

  /// An output: the block computes it.
  output,

  /// An input that holds no typed value: it takes a wire.
  input,
}

/// Why a typed text is refused.
enum FieldEditError { number, json, toggle }

/// How the value of [f] of [b] is typed, or why it is not. The inspector's
/// row and the value viewer's edit mode read the same answer.
({FieldEdit? edit, FieldLocked? locked}) fieldEditOf(
  FlowBlock b,
  FlowField f,
  Iterable<FlowEdge> edges,
) {
  if (f.inPort != null &&
      edges.any((e) => e.to == b.id && e.toPort == f.inPort)) {
    return (edit: null, locked: FieldLocked.bound);
  }
  if (f.spec case final p?) {
    return (
      edit: p.choices.isNotEmpty
          ? FieldEdit.choice
          : switch (p.type) {
              'bool' => FieldEdit.toggle,
              'number' || 'int' => FieldEdit.number,
              'map' || 'array' => FieldEdit.json,
              'dynamic' => FieldEdit.any,
              _ => FieldEdit.text,
            },
      locked: null,
    );
  }
  // An action's argument is typed as the action says (its choices, a
  // bool, a number); with no word of the action, as any value.
  if (f.argSpec case final p?) {
    return (
      edit: p.choices.isNotEmpty
          ? FieldEdit.choice
          : switch (p.type) {
              'bool' => FieldEdit.toggle,
              'number' || 'int' => FieldEdit.number,
              'map' || 'array' => FieldEdit.json,
              'string' || 'enum' => FieldEdit.text,
              _ => FieldEdit.any,
            },
      locked: null,
    );
  }
  // A range text (`date_range` `in`) stays a text: `2026` is a year to
  // the engine, not the number JSON would make of it.
  if (f.operand && isRangeText(b.type, f.name)) {
    return (edit: FieldEdit.text, locked: null);
  }
  if (f.kind == FieldKind.arg || f.operand) {
    return (edit: FieldEdit.any, locked: null);
  }
  return (
    edit: null,
    locked: f.kind == FieldKind.output ? FieldLocked.output : FieldLocked.input,
  );
}

/// The typed value of [f] of [b] as the text its editor starts with: the
/// config's value, else the parameter's default; a map or a list as
/// indented JSON; a text as itself.
String fieldEditText(FlowBlock b, FlowField f) {
  final v = switch (f) {
    FlowField(:final spec?) => b.cfg[spec.name] ?? spec.defaultValue,
    FlowField(kind: FieldKind.arg) => (b.cfg['args'] as Map?)?[f.name],
    FlowField(operand: true, :final inPort?) => operandValueOf(b, inPort),
    _ => null,
  };
  return switch (v) {
    null => '',
    final String s => s,
    final Map<Object?, Object?> m => flowJson(m),
    final List<Object?> l => flowJson(l),
    _ => jsonEncode(v),
  };
}

/// What is wrong with [text] as a value typed by [edit]; null when it can
/// be saved. Empty text is always right: it removes the value.
FieldEditError? fieldEditError(String text, FieldEdit edit) {
  final s = text.trim();
  if (s.isEmpty) {
    return null;
  }
  switch (edit) {
    case FieldEdit.number:
      final n = num.tryParse(s);
      return n == null || !n.isFinite ? FieldEditError.number : null;
    case FieldEdit.json:
      try {
        final v = jsonDecode(s);
        return v is Map || v is List ? null : FieldEditError.json;
      } on FormatException {
        return FieldEditError.json;
      }
    case FieldEdit.toggle:
      return s == 'true' || s == 'false' ? null : FieldEditError.toggle;
    case FieldEdit.choice || FieldEdit.text || FieldEdit.any:
      return null;
  }
}

/// [text] as the value an editor of kind [edit] writes into the config: a
/// number, a bool, a decoded structure; else the text itself. A text that
/// does not read as its kind stays a text (the engine's validation says
/// what is wrong with it).
Object? typedText(String text, FieldEdit edit) {
  final s = text.trim();
  switch (edit) {
    case FieldEdit.number:
      return num.tryParse(s) ?? text;
    case FieldEdit.toggle:
      return s == 'true' ? true : (s == 'false' ? false : text);
    case FieldEdit.json:
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    case FieldEdit.any:
      if (s.isEmpty) {
        return text;
      }
      try {
        return jsonDecode(s);
      } on FormatException {
        return text;
      }
    case FieldEdit.choice || FieldEdit.text:
      return text;
  }
}
