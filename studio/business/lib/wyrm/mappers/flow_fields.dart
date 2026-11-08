import 'dart:math' as math;

import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/quality.dart';

import 'flow_mapper.dart';
import 'value_text.dart';

// The flow editor draws a block as fields, not as engine ports
// (studio/docs/design/specs/flow-editor.md §3, ADR 0038): one row per
// parameter and per input with its value, a left port where the engine
// takes an input and a right port where the field feeds other blocks.
// Edges in the definition stay engine ports (`in.<p>`, `in`, `in.0`, `out`,
// and the echo outputs named like the field).

/// What a field is in the engine.
enum FieldKind {
  /// A parameter of the node's config (`cfg.<name>`).
  param,

  /// An input port that is not a parameter's port (`in`, `in.0`, `reset`).
  input,

  /// An output port (`out`, `remainder`, …).
  output,

  /// An argument of an `invoke` block's `args` map: shown, not wired.
  arg,
}

/// The editor's kind of block (spec §3 header chip and colour).
enum BlockRole {
  /// A point of the tree: `subscribe`, `liveliness` (reads), `set` (writes).
  node,

  /// Logic between them.
  logic,

  /// `publish`: a value of the flow.
  sink,

  /// `invoke`: an action of the tree.
  action,
}

/// Types that read a point (`key`) and that write one (`path`).
const _reads = {'subscribe', 'liveliness'};
const _sinks = {'publish', 'set', 'invoke'};

/// Inputs into these write to a device (ember wires, spec §4).
const writingTypes = {'set', 'invoke'};

/// The role of a block of [type].
BlockRole roleOf(String type) => switch (type) {
  'subscribe' || 'liveliness' || 'set' => BlockRole.node,
  'publish' => BlockRole.sink,
  'invoke' => BlockRole.action,
  _ => BlockRole.logic,
};

/// The width a block of [role] is drawn at (spec §3: 200–220, 210 for sinks).
double blockWidthOf(BlockRole role) => switch (role) {
  BlockRole.node => 200,
  BlockRole.logic => 220,
  BlockRole.sink || BlockRole.action => 210,
};

/// The point a `subscribe`, `liveliness`, `set` or `invoke` block names
/// (`key` or `path`), relative to the site or full.
String? pointOf(FlowBlock b) =>
    switch (b.cfg[_reads.contains(b.type) ? 'key' : 'path']) {
      final String k when k.isNotEmpty => k,
      _ => null,
    };

/// One field of a block.
final class FlowField {
  const FlowField({
    required this.id,
    required this.label,
    required this.kind,
    this.inPort,
    this.outPort,
    this.spec,
    this.onBlock = true,
  });

  /// Unique within the block: `p:<name>`, `in:<port>`, `out:<port>`,
  /// `arg:<name>`.
  final String id;

  /// What the row reads (`input_min`, `0`, `out`); never `in.<p>`.
  final String label;
  final FieldKind kind;

  /// The engine input an edge into this field uses; null: no left port.
  final String? inPort;

  /// The engine output an edge out of this field uses; null: no right port.
  final String? outPort;

  /// The parameter behind a [FieldKind.param] field.
  final ParamSpec? spec;

  /// Drawn as a row of the block; the inspector lists every field.
  final bool onBlock;

  /// A parameter whose value is typed (the def's `cfg`).
  bool get typed => kind == FieldKind.param;

  @override
  bool operator ==(Object other) =>
      other is FlowField &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.inPort == inPort &&
      other.outPort == outPort &&
      other.onBlock == onBlock;

  @override
  int get hashCode => Object.hash(id, label, kind, inPort, outPort, onBlock);

  @override
  String toString() =>
      'FlowField($label ${inPort ?? '-'} → ${outPort ?? '-'}'
      '${onBlock ? '' : ' hidden'})';
}

/// The variable inputs of a block (`inputs` of `add`, `if`, `expression`):
/// what − and + change.
final class Variadic {
  const Variadic({
    required this.param,
    required this.prefix,
    required this.names,
    required this.min,
  });

  /// The list parameter (`inputs`).
  final String param;

  /// Each name's port prefix (`in.`).
  final String prefix;
  final List<String> names;

  /// Fewer is refused (the type's default count, at least 1).
  final int min;

  /// The name + adds: the next free number when every name is one, else
  /// the next free letter.
  String get next {
    final numeric = names.every((n) => int.tryParse(n) != null);
    if (numeric && (names.isNotEmpty || min > 0)) {
      var i = 0;
      while (names.contains('$i')) {
        i++;
      }
      return '$i';
    }
    for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++) {
      final s = String.fromCharCode(c);
      if (!names.contains(s)) {
        return s;
      }
    }
    var i = names.length;
    while (names.contains('in$i')) {
      i++;
    }
    return 'in$i';
  }
}

/// The variable inputs of [b], if its type has a list of them.
Variadic? variadicOf(NodeType? t, FlowBlock b) {
  final param = t?.dynInParam;
  if (t == null || param == null || t.dynOutParam != null) {
    return null;
  }
  final names = switch (b.cfg[param]) {
    final List<Object?> l => [
      for (final n in l)
        if (n is String && n.isNotEmpty) n,
    ],
    _ => t.dynInDefaults.toList(),
  };
  return Variadic(
    param: param,
    prefix: t.dynInPrefix,
    names: names,
    min: math.max(1, t.dynInDefaults.length),
  );
}

/// The fields of [b] in the order a block draws them: fixed inputs that are
/// no parameter's, then the parameters (each with its input port where the
/// engine has one), then the variable inputs, then the outputs.
///
/// With ADR 0038 the catalog says each parameter's `port` and `echo`;
/// without it a parameter `p` has the port `in.<p>` when the type lists it,
/// and every field of a non-sink block has an output named like it (the
/// engine's echo). An echo never takes the name of an existing output, and
/// two fields never share one: outputs first, then parameters, then inputs;
/// a parameter named like an input gives neither an echo.
List<FlowField> fieldsOf(NodeType? t, FlowBlock b) {
  if (t == null) {
    return const [
      FlowField(id: 'in:in', label: 'in', kind: .input, inPort: 'in'),
      FlowField(id: 'out:out', label: 'out', kind: .output, outPort: 'out'),
    ];
  }
  final role = roleOf(b.type);
  final ports = portsOf(t, b);
  final sink = _sinks.contains(b.type);
  final echoInputs = !sink && (t.echoInputs ?? true);
  final dynParams = {?t.dynInParam, ?t.dynOutParam};
  // A parameter named like a fixed input (`latch` reset) has no echo, and
  // neither has that input: the two would share the name (ADR 0038 §1).
  final taken = <String>{
    ...ports.outputs,
    for (final p in t.params)
      if (t.inputs.contains(p.name)) p.name,
  };
  String? echo(String name, {required bool allowed}) {
    if (!allowed || taken.contains(name)) {
      return null;
    }
    taken.add(name);
    return name;
  }

  // Which parameter owns which input port.
  final portOf = <String, String>{};
  for (final p in t.params) {
    final port =
        p.port ?? (t.inputs.contains('in.${p.name}') ? 'in.${p.name}' : null);
    if (port != null) {
      portOf[p.name] = port;
    }
  }
  final paramPorts = portOf.values.toSet();
  final dynIns = ports.inputs.where((p) => !t.inputs.contains(p)).toList();
  final fixedIns = [
    for (final p in t.inputs)
      if (!paramPorts.contains(p)) p,
  ];
  String inLabel(String port) =>
      port.startsWith('in.') ? port.substring(3) : port;
  final node = role == BlockRole.node;
  final point = pointOf(b);
  final pointName = point?.split('/').last;

  // Parameters first take their echo names, then inputs (ADR 0038 §1).
  final params = <FlowField>[
    for (final p in t.params)
      if (!dynParams.contains(p.name))
        FlowField(
          id: 'p:${p.name}',
          label: p.name,
          kind: .param,
          spec: p,
          inPort: portOf[p.name],
          outPort: echo(p.name, allowed: !sink && (p.echo ?? true)),
          onBlock:
              !node &&
              !(role == BlockRole.action &&
                  (p.name == 'path' || p.name == 'args')) &&
              (portOf.containsKey(p.name) ||
                  b.cfg[p.name] != null ||
                  p.defaultValue != null ||
                  p.required),
        ),
  ];
  FlowField input(String port) => FlowField(
    id: 'in:$port',
    label: switch (b.type) {
      'publish' when port == 'in' => 'value',
      'set' when port == 'in' => pointName ?? 'in',
      'invoke' when port == 'in' => 'run when',
      _ => inLabel(port),
    },
    kind: .input,
    inPort: port,
    // A writable point repeats what it writes (spec §3, tree point).
    outPort: echo(
      port,
      allowed: echoInputs || (b.type == 'set' && (t.echoInputs ?? true)),
    ),
  );

  final fixed = [for (final p in fixedIns) input(p)];
  final dyn = [for (final p in dynIns) input(p)];
  final args = <FlowField>[
    if (b.type == 'invoke')
      if (b.cfg['args'] case final Map<String, Object?> m)
        for (final k in m.keys) FlowField(id: 'arg:$k', label: k, kind: .arg),
  ];
  final outs = <FlowField>[
    for (final p in ports.outputs)
      FlowField(
        id: 'out:$p',
        label: _reads.contains(b.type) && p == 'out' ? (pointName ?? p) : p,
        kind: .output,
        outPort: p,
      ),
  ];
  // A sink names what it writes before the value it writes (`publish`:
  // node, value).
  return role == BlockRole.sink
      ? [...params, ...fixed, ...dyn, ...args, ...outs]
      : [...fixed, ...params, ...dyn, ...args, ...outs];
}

/// The rows of [b] drawn on the canvas.
List<FlowField> rowsOf(NodeType? t, FlowBlock b) => [
  for (final f in fieldsOf(t, b))
    if (f.onBlock) f,
];

/// The height the editor draws [b] at: header 32, body padding 6 + 8, 28
/// per row, and the − / + row of a variable block.
double blockHeight(NodeType? t, FlowBlock b) {
  final rows = rowsOf(t, b).length;
  final tools = variadicOf(t, b) == null ? 0.0 : 38.0;
  return 32 + 6 + 28.0 * math.max(rows, 1) + 8 + tools;
}

/// The key of a live value of [node] in `flowEditor.ports`.
String portKey(String dir, String node, String port) => '$dir:$node.$port';

/// What a field shows.
final class FieldValue {
  const FieldValue(this.text, {this.bound = false, this.bad = false});

  final String text;

  /// An edge feeds it: the binding wins over the typed value.
  final bool bound;

  /// Its quality is bad.
  final bool bad;
}

/// The value [f] of block [b] shows: a bound field its last sample (else
/// its typed value), a parameter its typed value or default, an input or an
/// output its last sample. [live] reads `flowEditor.ports` (keys of
/// [portKey]) and, for a point, the tree's own value. A sample of a point
/// reads with its [unit] and [choices].
FieldValue fieldValue(
  FlowBlock b,
  FlowField f,
  FlowDraft d,
  LiveValue? Function(String key) live, {
  String? unit,
  List<String> choices = const [],
}) {
  final bound =
      f.inPort != null &&
      d.edges.any((e) => e.to == b.id && e.toPort == f.inPort);
  LiveValue? sample;
  Object? shown;
  switch (f.kind) {
    case FieldKind.param:
      final p = f.spec!;
      final typed = b.cfg[p.name] ?? p.defaultValue;
      sample = bound
          ? (live(portKey('in', b.id, f.inPort!)) ??
                live(portKey('param', b.id, p.name)))
          : null;
      shown =
          sample?.value ?? typed ?? live(portKey('param', b.id, p.name))?.value;
      if (sample == null && shown == null) {
        return FieldValue('', bound: bound);
      }
    case FieldKind.input:
      sample = live(portKey('in', b.id, f.inPort!));
      shown = sample?.value;
      if (sample == null) {
        return FieldValue('', bound: bound);
      }
    case FieldKind.output:
      sample = live(portKey('out', b.id, f.outPort!));
      shown = sample?.value;
      if (sample == null) {
        return const FieldValue('');
      }
    case FieldKind.arg:
      shown = (b.cfg['args'] as Map?)?[f.label];
  }
  final point = f.kind == FieldKind.input || f.kind == FieldKind.output;
  return FieldValue(
    switch (shown) {
      final Map<Object?, Object?> m when m.isNotEmpty => '{…}',
      final List<Object?> l when l.isNotEmpty => '[…]',
      _ when point && sample != null => valueText(
        shown,
        unit: unit,
        choices: choices,
      ),
      _ => valueText(shown),
    },
    bound: bound,
    bad: sample?.quality == Quality.bad,
  );
}
