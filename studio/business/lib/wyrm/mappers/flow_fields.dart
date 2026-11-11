import 'dart:convert';
import 'dart:math' as math;

import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/quality.dart';

import '../labels.dart';
import 'flow_blocks.dart';
import 'flow_mapper.dart';
import 'value_text.dart';

export '../labels.dart' show humanize;

// The flow editor draws a block as fields, not as engine ports
// (studio/docs/design/specs/flow-editor.md §3, ADR 0038; owner decision
// 2026-11-08): a field is ONE entity — its value, its binding and what it
// feeds — on one row. A field `p` is the parameter `p`, its input
// `in.<p>` and its echo output `p`; the main value of a variable block
// (`number`, `string`, `bool`, `const`: input `in`, parameter `value`,
// output `out`) is one field `Value`; an operator's operands (`in`,
// `in.0`, …) are fields with both ports, its result (`out`, `remainder`, …)
// a field with a right port only. Edges in the definition stay engine
// ports: binding INTO a field is an edge to its input, binding OUT of it an
// edge from its output.

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

  /// An instance of a custom block (`block:<name>`), and the two boundary
  /// blocks of a block's inside.
  custom,
}

/// Types that read a point (`key`) and that write one (`path`).
const _reads = {'subscribe', 'liveliness'};

/// Types whose point is their `key`; the others name it `path`.
const _keyed = {
  'subscribe',
  'liveliness',
  'load_value',
  'load_history',
  'get_node',
};
const _sinks = {'publish', 'set', 'invoke'};

/// Inputs into these write to a device (ember wires, spec §4).
const writingTypes = {'set', 'invoke'};

/// The role of a block of [type].
BlockRole roleOf(String type) => switch (type) {
  'subscribe' || 'liveliness' || 'set' => BlockRole.node,
  'publish' => BlockRole.sink,
  'invoke' => BlockRole.action,
  _ when type.startsWith('block') => BlockRole.custom,
  _ => BlockRole.logic,
};

/// The width a block of [role] is drawn at (spec §3: 200–220, 210 for sinks).
double blockWidthOf(BlockRole role) => switch (role) {
  BlockRole.node => 200,
  BlockRole.logic || BlockRole.custom => 220,
  BlockRole.sink || BlockRole.action => 210,
};

/// The point a `subscribe`, `liveliness`, `set` or `invoke` block names
/// (`key` or `path`), relative to the site or full.
String? pointOf(FlowBlock b) =>
    switch (b.cfg[_keyed.contains(b.type) ? 'key' : 'path']) {
      final String k when k.isNotEmpty => k,
      _ => null,
    };

/// One field of a block.
final class FlowField {
  const FlowField({
    required this.id,
    required this.name,
    required this.label,
    required this.kind,
    this.inPort,
    this.outPort,
    this.spec,
    this.argSpec,
    this.onBlock = true,
    this.outAliases = const [],
    this.variable = false,
    this.operand = false,
    this.command = false,
  });

  /// Unique within the block: `p:<name>`, `in:<port>`, `out:<port>`,
  /// `arg:<name>`.
  final String id;

  /// What the engine calls it: the parameter (`input_min`), the port
  /// (`in`, `in.0`, `quotient`) or the argument; shown small in the
  /// inspector and in the row's tooltip.
  final String name;

  /// What the row reads: [fieldLabel] (`Input min`, `Input 1`, `Output`),
  /// a point's own name, an argument's key; never `in.<p>`, no colon.
  final String label;
  final FieldKind kind;

  /// The engine input an edge into this field uses; null: no left port.
  final String? inPort;

  /// The engine output an edge out of this field uses; null: no right port.
  final String? outPort;

  /// The parameter behind a [FieldKind.param] field.
  final ParamSpec? spec;

  /// What the action says of this argument (a [FieldKind.arg] field of an
  /// `invoke`): its type, choices and whether it is required. Null when the
  /// node's actions are not read yet.
  final ParamSpec? argSpec;

  /// Pinned to the block by default (the type's main inputs, outputs and
  /// the fields users set most); the user's choice for one block wins
  /// ([fieldPinned]). The inspector lists every field.
  final bool onBlock;

  /// Other engine outputs that leave this field: a variable's `value` and
  /// `in` echoes, which an older definition may have wired. A new binding
  /// out of the field always uses [outPort].
  final List<String> outAliases;

  /// The main value of a variable block (`Value`): the parameter `value`,
  /// the input `in` and the output `out` as one field.
  final bool variable;

  /// An operand input that holds a typed constant (`values.<inPort>`, ADR
  /// 0038 §7): its value until a binding replaces it; the constant stays
  /// in the config while bound and returns on unbind.
  final bool operand;

  /// An input that is a command ([commandInputs]: `date_range` `next`,
  /// `table_page` `first`): a button that a sample on its wire presses,
  /// not a value. It holds no typed value and shows none.
  final bool command;

  /// Whether an edge out of [port] leaves this field.
  bool sends(String port) => port == outPort || outAliases.contains(port);

  /// A parameter whose value is typed (the def's `cfg`).
  bool get typed => kind == FieldKind.param;

  @override
  bool operator ==(Object other) =>
      other is FlowField &&
      other.id == id &&
      other.name == name &&
      other.label == label &&
      other.kind == kind &&
      other.inPort == inPort &&
      other.outPort == outPort &&
      other.onBlock == onBlock &&
      other.variable == variable &&
      other.operand == operand &&
      other.command == command &&
      _same(other.outAliases, outAliases);

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    label,
    kind,
    inPort,
    outPort,
    onBlock,
    variable,
    operand,
    command,
    Object.hashAll(outAliases),
  );

  @override
  String toString() =>
      'FlowField($name "$label" ${inPort ?? '-'} → ${outPort ?? '-'}'
      '${onBlock ? '' : ' hidden'}${operand ? ' operand' : ''}'
      '${command ? ' command' : ''})';
}

/// The variable inputs of a block (`inputs` of `add`, `if`, `expression`):
/// what − and + change.
final class Variadic {
  const Variadic({
    required this.param,
    required this.prefix,
    required this.names,
    required this.min,
    this.step = 1,
    this.outPrefix,
  });

  /// The list parameter (`inputs`).
  final String param;

  /// Each name's port prefix (`in.`).
  final String prefix;

  /// Each name's output prefix when the list names outputs too (`router`:
  /// `out.`, a case and its output are one field); null: inputs only.
  final String? outPrefix;
  final List<String> names;

  /// Fewer is refused (the type's default count, at least 1).
  final int min;

  /// How many names one − or + takes away or adds: 2 for a block whose
  /// inputs come in pairs (`case`: a case, then what it gives).
  final int step;

  /// The names + adds: [step] free names after [names].
  List<String> get adds {
    final out = <String>[];
    var v = this;
    for (var i = 0; i < step; i++) {
      final n = v.next;
      out.add(n);
      v = Variadic(
        param: param,
        prefix: prefix,
        names: [...v.names, n],
        min: min,
        outPrefix: outPrefix,
      );
    }
    return out;
  }

  /// The names − takes away: the last [step]; none at [min].
  List<String> get removes =>
      names.length - step < min ? const [] : names.sublist(names.length - step);

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

/// The variable inputs of [b], if its type has a list of them. A list that
/// names outputs too (`router`: `in.<case>` and `out.<case>`) changes both
/// ([Variadic.outPrefix]); one that names other outputs (`wasm`) is no
/// list of inputs.
Variadic? variadicOf(NodeType? t, FlowBlock b) {
  final param = t?.dynInParam;
  if (t == null ||
      param == null ||
      (t.dynOutParam != null && t.dynOutParam != param) ||
      t.dynInKeys) {
    return null;
  }
  final names = switch (b.cfg[param]) {
    final List<Object?> l => [
      for (final n in l)
        if (n is String && n.isNotEmpty) n,
    ],
    _ => t.dynInDefaults.toList(),
  };
  final step = pairedInputs.contains(b.type) ? 2 : 1;
  return Variadic(
    param: param,
    prefix: t.dynInPrefix,
    names: names,
    min: math.max(step, t.dynInDefaults.length),
    step: step,
    outPrefix: t.dynOutParam == param ? t.dynOutPrefix : null,
  );
}

/// Whether blocks of [t] name an output for each variable input
/// (`router`): the input `in.<case>` and the output `out.<case>` are one
/// field, its case on the left and what it routes on the right.
bool pairsOutputs(NodeType? t) =>
    t != null &&
    t.dynInParam != null &&
    t.dynInParam == t.dynOutParam &&
    !t.dynInKeys;

/// What a case of a `router` reads: `Case 1` for the name `0`, else the
/// name the user gave it (`high`).
String caseLabel(String name) => switch (int.tryParse(name)) {
  final n? => 'Case ${n + 1}',
  null => name,
};

/// Block types whose variable inputs come in pairs: `case` (a case value,
/// then what it gives; ADR 0038 §8).
const pairedInputs = {'case'};

/// What the variable input at [index] of a paired block reads: `Case 1`,
/// `Then 1`, `Case 2`, … (flow-editor.md §3: labels by position, as the
/// engine reads the pairs by position).
String pairLabel(int index) =>
    '${index.isEven ? 'Case' : 'Then'} ${index ~/ 2 + 1}';

// ---------- labels (flow-editor.md §3, owner decision 2026-11-08) ----------

/// Names whose sentence-case form reads wrong or says too little. A key
/// `<type>.<name>` names a parameter of that type and wins over `<name>`
/// (`latch` has an input and a parameter both named `reset`).
const fieldLabelOverrides = <String, String>{
  'in': 'Input',
  'out': 'Output',
  'k': 'Factor',
  'b': 'Offset',
  'abs': 'Absolute change',
  'pct': 'Percent change',
  'fn': 'Function',
  'op': 'Operation',
  'expr': 'Expression',
  'msg': 'Message',
  'ms': 'Delay (ms)',
  'key': 'Point',
  'node': 'Value name',
  'meta': 'Meta',
  'allow_bad': 'Allow bad quality',
  'on_bad': 'On bad quality',
  'max_samples': 'Max samples',
  'memory_mb': 'Memory (MB)',
  'input_out_of_range': 'Input out of range',
  'latch.reset': 'Reset mode',
  // A liveliness token belongs to a node, not to a point.
  'liveliness.key': 'Node',
  'set.path': 'Point',
  'set.on': 'Write on',
  'invoke.path': 'Node',
  'invoke.on': 'Run on',
  'stopwatch.interval': 'Interval (s)',
  // ADR 0040: behaviours, scopes, the second set of blocks.
  'trigger': 'Trigger',
  'interval_ms': 'Every',
  'auto_run': 'Auto run',
  'run_on_start': 'Run on start',
  'key_scope': 'Scope',
  'path_scope': 'Scope',
  'list_children.path': 'Node',
  'throttle.ms': 'Period (ms)',
  'debounce.ms': 'Quiet time (ms)',
  // ADR 0044: the third set (docs/flow-blocks.md, the editor's table).
  'get_node.key': 'Node',
  'date_range.range_delimiter': 'Delimiter',
};

/// Inputs that are commands, not values: a sample on the wire presses them
/// (docs/flow-blocks.md: `date_range` moves to the next or the previous
/// range, `table_page` to a page). The editor draws them as buttons.
const commandInputs = <String, Set<String>>{
  'date_range': {'next', 'previous'},
  'table_page': {'next', 'previous', 'first', 'last'},
};

/// The fields that hold a date: microseconds since the Unix epoch (ADR 0044
/// §3). The editor shows such a value as a date and time; the viewer adds
/// the instant in UTC and the number. `date_range.duration` is a length of
/// time, not a date.
const timeFields = <String, Set<String>>{
  'now': {'out'},
  'date_time': {'out'},
  'date_parse': {'in', 'time'},
  'date_format': {'in'},
  'date_math': {'in', 'out'},
  'date_range': {'start', 'end'},
};

/// Whether field [name] (a port) of a block of [type] holds a date
/// ([timeFields]).
bool isTimeField(String type, String name) =>
    timeFields[type]?.contains(name) ?? false;

/// The time zone parameters of the date blocks (ADR 0044 §3): an IANA name,
/// `UTC` or `±HH:MM`; `date_format` also takes `auto`.
bool isTimeZoneParam(String type, String name) =>
    name == 'time_zone' &&
    const {
      'date_time',
      'date_format',
      'date_parse',
      'date_math',
      'date_range',
      'load_history',
      'table_rollup',
    }.contains(type);

/// The fields that hold a range text as `date_range` reads it (`today`,
/// `lastWeek`, `current24hours`, `2026-10`, `<a>/<b>`): the operand `in`
/// of `date_range` and the parameter `time_range` of `load_history`.
bool isRangeText(String type, String name) =>
    type == 'date_range' && name == 'in' ||
    type == 'load_history' && name == 'time_range';

/// The choices a range text offers (docs/flow-blocks.md, `date_range`); any
/// other text the engine reads (`2026-10`, `<a>/<b>`) is typed.
const rangeChoices = [
  'today',
  'yesterday',
  'thisWeek',
  'lastWeek',
  'thisMonth',
  'lastMonth',
  'thisYear',
  'lastYear',
  'current1hours',
  'current24hours',
  'current7days',
  'current30days',
  'previous24hours',
  'previous7days',
  'previous30days',
];

/// The time zones a time zone field offers: `UTC`, then the IANA names of
/// the main regions. Any other IANA name or an offset `±HH:MM` is typed;
/// the engine checks it against its own zone data (jiff's bundled tzdb).
const timeZoneChoices = [
  'UTC',
  'Europe/Kyiv',
  'Europe/London',
  'Europe/Lisbon',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/Brussels',
  'Europe/Vienna',
  'Europe/Zurich',
  'Europe/Stockholm',
  'Europe/Oslo',
  'Europe/Copenhagen',
  'Europe/Helsinki',
  'Europe/Warsaw',
  'Europe/Prague',
  'Europe/Budapest',
  'Europe/Bucharest',
  'Europe/Sofia',
  'Europe/Athens',
  'Europe/Istanbul',
  'Europe/Vilnius',
  'Europe/Riga',
  'Europe/Tallinn',
  'Europe/Chisinau',
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Lagos',
  'Asia/Dubai',
  'Asia/Tbilisi',
  'Asia/Kolkata',
  'Asia/Singapore',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Sydney',
  'Pacific/Auckland',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Toronto',
  'America/Mexico_City',
  'America/Sao_Paulo',
  'America/Buenos_Aires',
  '+02:00',
  '-05:00',
];

/// The choices of a time zone field of a block of [type]: `auto`
/// first for `date_format` (the offset written in the input text).
List<String> timeZoneChoicesOf(String type) => [
  if (type == 'date_format') 'auto',
  ...timeZoneChoices,
];

/// Whether field [name] of a block of type [t] may hold a table given as a
/// list of maps (ADR 0044 §2): the table inputs and outputs of the Tables
/// blocks, the rows a reader gives (`list_children`, `load_history`) and
/// the actions of `get_node`. A value `{columns, rows}` is a table
/// anywhere.
bool holdsTable(NodeType? t, String name) => switch ((t?.type, name)) {
  ('list_children' || 'load_history', 'out') => true,
  ('get_node', 'actions') => true,
  ('table', 'value' || 'out' || 'in') => true,
  (_, 'in' || 'right' || 'out') => t?.category == 'Tables',
  _ => false,
};

/// The methods of an aggregate (`crates/wyrm-flow/src/blocks/tables.rs`
/// `METHODS`), for a type whose catalog gives no `method` choices.
const aggregateMethods = [
  'first',
  'last',
  'count',
  'sum',
  'average',
  'min',
  'max',
  'median',
  'mode',
  'std_deviation',
  'variance',
  'concat',
  'concat_unique',
];

/// The keys of the items of a list parameter that the inspector edits as
/// rows (docs/flow-blocks.md, Tables): `mapping` `[{name, from}]`,
/// `aggregates` `[{column, method, as}]` with the method a choice (the
/// type's own `method` choices when its catalog has them). Null for any
/// other parameter.
List<({String key, List<String> choices})>? listItemsOf(
  NodeType? t,
  String name,
) {
  switch ((t?.type, name)) {
    case ('table_map_columns', 'mapping'):
      return const [(key: 'name', choices: []), (key: 'from', choices: [])];
    case ('table_group_by' || 'table_rollup', 'aggregates'):
      final listed = t?.params
          .where((p) => p.name == 'method')
          .firstOrNull
          ?.choices;
      return [
        (key: 'column', choices: const []),
        (
          key: 'method',
          choices: listed == null || listed.isEmpty
              ? aggregateMethods
              : listed.unlock,
        ),
        (key: 'as', choices: const []),
      ];
    default:
      return null;
  }
}

/// The items of a list parameter as rows of texts by key ([listItemsOf]):
/// a text as it is, another value as JSON. A value that is no list of maps
/// gives no rows.
List<Map<String, String>> listRowsOf(Object? v) => [
  if (v case final List<Object?> l)
    for (final item in l)
      if (item case final Map<Object?, Object?> m)
        {
          for (final MapEntry(:key, :value) in m.entries)
            '$key': switch (value) {
              null => '',
              final String s => s,
              _ => jsonEncode(value),
            },
        },
];

/// Whether input [port] of a block of [type] is a command ([commandInputs]).
bool isCommandInput(String type, String port) =>
    commandInputs[type]?.contains(port) ?? false;

/// The palette's sections in order (flow-editor.md §2): where a value
/// comes from, the values, the calculations from the plainest, the logic,
/// text and its codecs, data and tables, time, then what the flow does to
/// the tree. A category the engine adds later comes after these, in the
/// catalog's order.
const paletteCategories = [
  'Sources',
  'Variables',
  'Math',
  'Trigonometry',
  'Statistics',
  'Logic',
  'Text',
  'Codecs',
  'Data',
  'Tables',
  'Date and time',
  'Alarms',
  'Outputs',
  'WASM',
];

/// [types] in the palette's order: by [paletteCategories], the catalog's
/// order within a category.
List<NodeType> inPaletteOrder(Iterable<NodeType> types) {
  final seen = <String>[];
  for (final t in types) {
    if (!seen.contains(t.category)) {
      seen.add(t.category);
    }
  }
  int rank(String c) {
    final i = paletteCategories.indexOf(c);
    return i >= 0 ? i : paletteCategories.length + seen.indexOf(c);
  }

  final all = types.toList();
  final at = {for (final (i, t) in all.indexed) t.type: i};
  return all..sort((a, b) {
    final r = rank(a.category).compareTo(rank(b.category));
    return r != 0 ? r : at[a.type]!.compareTo(at[b.type]!);
  });
}

/// What a block type reads in the palette and in a block's header: the
/// engine's name in sentence case (`rising_edge` → `Rising edge`,
/// `list_children` → `List children`); a custom block keeps the name its
/// author gave it.
String blockLabel(String type) =>
    blockNameOf(type) ?? _blockLabels[type] ?? humanize(type);

const _blockLabels = {'wasm': 'WASM'};

/// The fields that say when a command or a read runs (ADR 0040 §2).
const behaviourParams = {'interval_ms', 'auto_run', 'enabled', 'run_on_start'};

/// Whether blocks of [t] have behaviours: a `trigger` input and the event
/// outputs (`invoke`, `set`, `load_value`, `list_children` since ADR 0040).
bool behavesOf(NodeType? t) =>
    t != null && t.inputs.contains('trigger') && t.outputs.contains('last_run');

/// The inspector's groups of a block with behaviours (flow-editor.md §19).
enum FieldGroup { none, target, arguments, behaviour, events, state }

const _behaviourOrder = [
  'trigger',
  'in',
  'auto_run',
  'interval_ms',
  'enabled',
  'run_on_start',
  'on',
  'deadband',
  'allow_bad',
];

/// The group field [f] of [b] is listed under; [FieldGroup.none] for a
/// type without behaviours.
FieldGroup groupOf(NodeType? t, FlowBlock b, FlowField f) {
  if (!behavesOf(t)) {
    return FieldGroup.none;
  }
  return switch (f.kind) {
    FieldKind.arg => FieldGroup.arguments,
    FieldKind.param =>
      _behaviourOrder.contains(f.name)
          ? FieldGroup.behaviour
          : FieldGroup.target,
    FieldKind.input =>
      f.name == 'in' && b.type == 'set'
          ? FieldGroup.target
          : FieldGroup.behaviour,
    FieldKind.output =>
      const {'sent', 'ok', 'error'}.contains(f.name)
          ? FieldGroup.events
          : FieldGroup.state,
  };
}

/// Outputs that say more under their own name than as `Output`.
const outputLabelOverrides = <String, String>{
  'invoke.out': 'Result',
  'stats.avg': 'Average',
  'alarm.out': 'Active',
  'timer.out': 'Count',
  'constant.out': 'Value',
};

/// Parameters a block of a type lists in the inspector only, though they
/// have a port or a default (docs/flow-blocks.md, the editor's table): the
/// rows that crowd the block and that few flows set. A wire or the user's
/// pin still puts them on the block.
const inspectorOnly = <String, Set<String>>{
  'load_history': {'limit', 'time_zone'},
  'table_filter': {'expr'},
  'table_remove_rows': {'expr'},
  'table_edit_rows': {'expr'},
};

/// Parameters of which the engine needs one or the other: both are rows
/// of the block, though neither has a default.
const _oneOf = <String, Set<String>>{
  'deadband': {'abs', 'pct'},
  'alarm': {'high', 'low'},
};

/// What a field named [name] of a block of [type] reads in Studio: the
/// catalog's own `display`, else an override ([fieldLabelOverrides]), else
/// [humanize]. Numbered inputs (`in.0`) read `Input 1`; other variable
/// inputs keep the name the user gave them (an `expression` variable, a
/// `wasm` port).
String fieldLabel(
  String type,
  String name, {
  ParamSpec? spec,
  bool variable = false,
}) {
  final display = spec?.display;
  if (display != null && display.isNotEmpty) {
    return display;
  }
  final short = name.startsWith('in.') ? name.substring(3) : name;
  if (variable) {
    final n = int.tryParse(short);
    return n == null ? short : 'Input ${n + 1}';
  }
  return (spec == null ? null : fieldLabelOverrides['$type.$short']) ??
      fieldLabelOverrides[short] ??
      humanize(short);
}

// ---------- forms (a block that does one of two things) ----------

/// One way a block of a type works, with the fields only it uses (ADR 0032
/// §7: `scale` is `k × in + b`, or a range map). The editor shows one form
/// at a time; the first is the default and needs nothing in the config.
final class BlockForm {
  const BlockForm(
    this.id,
    this.label, {
    this.params = const {},
    this.outputs = const {},
    this.defaults = const {},
  });

  final String id;

  /// What the inspector's choice reads.
  final String label;

  /// The parameters only this form uses (with their `in.<p>` ports and
  /// echo outputs).
  final Set<String> params;

  /// The outputs only this form sends.
  final Set<String> outputs;

  /// The engine's defaults of [params], for a catalog that does not give
  /// them (before ADR 0038).
  final Map<String, Object> defaults;

  /// Whether [name] (a parameter or an output) belongs to this form.
  bool owns(String name) => params.contains(name) || outputs.contains(name);
}

const _forms = <String, List<BlockForm>>{
  'scale': [
    BlockForm('linear', 'k × in + b', params: {'k', 'b'}),
    BlockForm(
      'range',
      'Range',
      params: {'input_min', 'input_max', 'output_min', 'output_max'},
      outputs: {'input_out_of_range'},
      defaults: {
        'input_min': 0,
        'input_max': 1,
        'output_min': 0,
        'output_max': 100,
      },
    ),
  ],
};

/// The forms of a block of [type]; empty for a type with one.
List<BlockForm> formsOf(String type) => _forms[type] ?? const [];

/// The form [b] is in: a later form once one of its parameters is in the
/// config or an edge feeds one of their ports (the engine switches on
/// then), else the first.
BlockForm? formOf(FlowBlock b, Iterable<FlowEdge> edges) {
  final forms = formsOf(b.type);
  if (forms.isEmpty) {
    return null;
  }
  for (final f in forms.skip(1)) {
    final given = f.params.any(
      (p) =>
          b.cfg[p] != null ||
          edges.any((e) => e.to == b.id && e.toPort == 'in.$p'),
    );
    if (given) {
      return f;
    }
  }
  return forms.first;
}

/// Whether the field [name] of [b] (a parameter or an output) belongs to a
/// form [b] is not in, and nothing keeps it: neither the config nor an
/// edge. Such a field is not shown.
bool _otherForm(FlowBlock b, String name, Iterable<FlowEdge> edges) {
  final form = formOf(b, edges);
  if (form == null || form.owns(name)) {
    return false;
  }
  final other = formsOf(b.type).any((f) => f.owns(name));
  if (!other) {
    return false;
  }
  final kept =
      b.cfg[name] != null ||
      edges.any(
        (e) =>
            (e.to == b.id && e.toPort == 'in.$name') ||
            (e.from == b.id && e.fromPort == name),
      );
  return !kept;
}

// ---------- the fields of a block ----------

/// The fields of [b] in the order a block draws them: fixed inputs that are
/// no parameter's, then the parameters (each with its input port where the
/// engine has one), then the variable inputs, then the outputs. [edges] are
/// the draft's: they decide the form of a block with two (`scale`).
///
/// With ADR 0038 the catalog says each parameter's `port` and `echo`;
/// without it a parameter `p` has the port `in.<p>` when the type lists it,
/// and every field of a non-sink block has an output named like it (the
/// engine's echo). Echoes are named as the engine names them
/// (`catalog.rs` `echoes`): a declared output keeps its name, then inputs
/// take theirs, then parameters; so `latch`'s input `reset` has an echo and
/// its parameter `reset` has none.
List<FlowField> fieldsOf(
  NodeType? t,
  FlowBlock b, {
  Iterable<FlowEdge> edges = const [],
  Iterable<ParamSpec> actionParams = const [],
}) {
  if (t == null) {
    return const [
      FlowField(
        id: 'in:in',
        name: 'in',
        label: 'Input',
        kind: .input,
        inPort: 'in',
      ),
      FlowField(
        id: 'out:out',
        name: 'out',
        label: 'Output',
        kind: .output,
        outPort: 'out',
      ),
    ];
  }
  // A variable (`number`, `string`, `bool`, `const`): its input, its
  // parameter and its output are one field (spec §3).
  if (isVariable(t)) {
    final p = t.params.first;
    return [
      FlowField(
        id: 'p:${p.name}',
        name: p.name,
        label: fieldLabel(b.type, p.name, spec: p),
        kind: .param,
        spec: p,
        inPort: t.inputs.contains('in') ? 'in' : null,
        outPort: 'out',
        outAliases: [
          if (p.echo ?? true) p.name,
          if (t.inputs.contains('in') && (t.echoInputs ?? true)) 'in',
        ],
        variable: true,
      ),
    ];
  }
  final role = roleOf(b.type);
  final ports = portsOf(t, b);
  final sink = _sinks.contains(b.type);
  final echoInputs = !sink && (t.echoInputs ?? true);
  final dynParams = {?t.dynInParam, ?t.dynOutParam};

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
  final operands = operandPortsOf(t, b).toSet();
  // An `invoke` argument is a field of its own kind (`arg:<name>`), not a
  // variable input.
  final dynIns = t.dynInKeys
      ? const <String>[]
      : ports.inputs.where((p) => !t.inputs.contains(p)).toList();
  final instance = isInstance(b.type);
  final behaves = behavesOf(t);
  // The key field that takes a wire inside a scope (ADR 0040 §1).
  final keyed = scopedKeyOf(t);
  final keyBound =
      keyed != null && edges.any((e) => e.to == b.id && e.toPort == keyed.port);
  final fixedIns = [
    for (final p in t.inputs)
      if (!paramPorts.contains(p)) p,
  ];

  // Echo names in the engine's order: outputs are taken, then inputs, then
  // parameters (ADR 0038 §1).
  final taken = <String>{...ports.outputs};
  final inEcho = <String, String>{};
  // A case of a `router` leaves by its own output, not by an echo.
  final routed = pairsOutputs(t);
  for (final port in [...fixedIns, if (!routed) ...dynIns]) {
    final allowed =
        echoInputs ||
        (b.type == 'set' && port == 'in' && (t.echoInputs ?? true));
    if (allowed && taken.add(port)) {
      inEcho[port] = port;
    }
  }
  final paramEcho = <String, String>{};
  for (final p in t.params) {
    final allowed = !sink && (p.echo ?? true) && !dynParams.contains(p.name);
    if (allowed && taken.add(p.name)) {
      paramEcho[p.name] = p.name;
    }
  }

  final node = role == BlockRole.node;
  final form = formOf(b, edges);
  final point = pointOf(b);
  final pointName = point?.split('/').last;

  final params = <FlowField>[
    for (final p in t.params)
      if (!dynParams.contains(p.name) && !_otherForm(b, p.name, edges))
        FlowField(
          id: 'p:${p.name}',
          name: p.name,
          label: fieldLabel(b.type, p.name, spec: p),
          kind: .param,
          spec: p,
          inPort: portOf[p.name],
          // A scope is read on the block and typed in its prompt: it
          // feeds nothing.
          outPort: p.name == keyed?.scope ? null : paramEcho[p.name],
          onBlock: switch (p.name) {
            // The key takes a wire: it is a row with a left port.
            final n when n == keyed?.key => true,
            // Its scope shows once it matters: a wire feeds the key, or
            // a scope is written.
            final n when n == keyed?.scope => keyBound || b.cfg[n] != null,
            // Behaviours are set in the inspector; one that is set shows.
            final n when behaves && behaviourParams.contains(n) =>
              b.cfg[n] != null,
            // The action block names its action in its header.
            'action' || 'on' when behaves && role == BlockRole.action => false,
            final n when inspectorOnly[b.type]?.contains(n) ?? false => false,
            _ =>
              !node &&
                  !(role == BlockRole.action &&
                      const {
                        'path',
                        'args',
                        'allow_bad',
                      }.contains(p.name)) &&
                  (portOf.containsKey(p.name) ||
                      (form?.params.contains(p.name) ?? false) ||
                      (_oneOf[b.type]?.contains(p.name) ?? false) ||
                      b.cfg[p.name] != null ||
                      p.defaultValue != null ||
                      p.required),
          },
        ),
  ];
  FlowField input(String port, {required bool variable, int index = 0}) {
    final command = !variable && isCommandInput(b.type, port);
    final name = port.startsWith(t.dynInPrefix)
        ? port.substring(t.dynInPrefix.length)
        : port;
    return FlowField(
      id: 'in:$port',
      name: port,
      label: switch (b.type) {
        'publish' when port == 'in' => 'Value',
        'set' when port == 'in' => pointName ?? 'Input',
        'invoke' when port == 'in' => 'Run when',
        // A custom block's ports keep the names their author gave them.
        _ when instance => port,
        _ when variable && pairedInputs.contains(b.type) => pairLabel(index),
        _ when variable && routed => caseLabel(name),
        _ => fieldLabel(b.type, port, variable: variable),
      },
      kind: .input,
      inPort: port,
      // A writable point repeats what it writes (spec §3, tree point); a
      // case of a `router` sends on its own output; a command (a button)
      // feeds nothing, though an older wire out of its echo still draws.
      outPort: variable && routed
          ? '${t.dynOutPrefix}$name'
          : (command ? null : inEcho[port]),
      outAliases: [if (command) ?inEcho[port]],
      command: command,
      operand: operands.contains(port),
      // The action block runs on its trigger: the older `in` stays in
      // the inspector. A `set` is its point; its trigger is set there too.
      onBlock:
          !behaves ||
          !(port == 'in' && b.type == 'invoke' || port == 'trigger' && node),
    );
  }

  final fixed = [for (final p in fixedIns) input(p, variable: false)];
  final dyn = [
    for (final (i, p) in dynIns.indexed) input(p, variable: true, index: i),
  ];
  // An action's arguments: the keys of `args`, each a field with the port
  // `arg.<name>` where the engine has it (ADR 0040 §2), then the
  // parameters of the action that have no key yet (inspector only: typing
  // a value or binding one adds the key).
  final argKeys = <String>[
    if (b.type == 'invoke')
      if (b.cfg['args'] case final Map<Object?, Object?> m)
        for (final k in m.keys)
          if (k is String) k,
  ];
  final argSpecs = {for (final p in actionParams) p.name: p};
  FlowField arg(String k, {required bool has}) => FlowField(
    id: 'arg:$k',
    name: k,
    label: argSpecs[k]?.display ?? k,
    kind: .arg,
    inPort: t.dynInKeys ? '${t.dynInPrefix}$k' : null,
    argSpec: argSpecs[k],
    onBlock: has,
  );
  final args = <FlowField>[
    for (final k in argKeys) arg(k, has: true),
    if (b.type == 'invoke')
      for (final p in actionParams)
        if (!argKeys.contains(p.name)) arg(p.name, has: false),
  ];
  // The outputs of the cases of a `router` are the cases' own fields.
  final caseOuts = {
    if (routed)
      for (final p in dynIns)
        '${t.dynOutPrefix}${p.substring(t.dynInPrefix.length)}',
  };
  final outs = <FlowField>[
    for (final p in ports.outputs)
      if (!_otherForm(b, p, edges) && !caseOuts.contains(p))
        FlowField(
          id: 'out:$p',
          name: p,
          label: _reads.contains(b.type) && p == 'out'
              ? (pointName ?? fieldLabel(b.type, p))
              : (instance || t.dynOutParam != null && !t.outputs.contains(p)
                    ? p
                    : (b.type == 'invoke' && p == 'out' && behaves
                          ? fieldLabel(b.type, p)
                          : outputLabelOverrides['${b.type}.$p'] ??
                                fieldLabel(b.type, p))),
          kind: .output,
          outPort: p,
          onBlock: switch (p) {
            // A refused key says why on `error`: a row once a wire feeds
            // the key.
            'error' when keyed != null && !behaves => keyBound,
            _ when !behaves => true,
            // A `set` is its point; its events are wired from the
            // inspector.
            _ when node => false,
            'error' => true,
            'ok' => b.type == 'invoke',
            'out' => b.type != 'invoke',
            _ => false,
          },
        ),
  ];
  // A sink names what it writes before the value it writes (`publish`:
  // node, value). Elsewhere the order is: operands, parameters, variable
  // inputs, then the trailing parameters ([tailParams]: `if` then, else;
  // `concat` strict), results.
  final tail = tailParams[b.type] ?? const <String>{};
  final head = [
    for (final f in params)
      if (!tail.contains(f.name)) f,
  ];
  final after = [
    for (final f in params)
      if (tail.contains(f.name)) f,
  ];
  final all = role == BlockRole.sink
      ? [...params, ...fixed, ...dyn, ...args, ...outs]
      : [...fixed, ...head, ...dyn, ...after, ...args, ...outs];
  if (!behaves) {
    return all;
  }
  // A block with behaviours lists its fields by group (flow-editor.md
  // §19): what it acts on, its arguments, when it runs, what happened.
  int rank(FlowField f) {
    final i = _behaviourOrder.indexOf(f.name);
    return i < 0 ? _behaviourOrder.length : i;
  }

  final order = {for (final (i, f) in all.indexed) f.id: i};
  return all..sort((x, y) {
    final gx = groupOf(t, b, x);
    final gy = groupOf(t, b, y);
    if (gx != gy) {
      return gx.index.compareTo(gy.index);
    }
    final byRank = gx == FieldGroup.behaviour ? rank(x).compareTo(rank(y)) : 0;
    return byRank != 0 ? byRank : order[x.id]!.compareTo(order[y.id]!);
  });
}

/// The trailing parameters: drawn after a block's variable inputs (order:
/// operands, parameters, variable inputs, then these, results). `if` reads
/// Operation · Input 1… · Then · Else · Output, `concat` Input 1… · Strict
/// · Output, `hub` Input 1… · Ignore null · Output · Index · On change.
const tailParams = <String, Set<String>>{
  'if': {'then', 'else'},
  'concat': {'strict'},
  'hub': {'ignore_null'},
  'case': {'else'},
  // ADR 0044 (docs/flow-blocks.md, the editor's table).
  'router': {'single_output'},
  'table_recorder': {'enabled', 'buffer_size', 'time_window_s', 'ignore_null'},
};

/// Whether blocks of [t] are variables: one parameter `value`, at most the
/// input `in`, the one output `out` (`number`, `string`, `bool`, `const`).
bool isVariable(NodeType? t) =>
    t != null &&
    t.params.length == 1 &&
    t.params.first.name == 'value' &&
    t.outputs.length == 1 &&
    t.outputs.first == 'out' &&
    t.inputs.every((p) => p == 'in') &&
    t.dynInParam == null &&
    t.dynOutParam == null;

/// Whether a wire of [edges] goes into [f] of [b] or leaves it.
bool fieldBound(FlowBlock b, FlowField f, Iterable<FlowEdge> edges) =>
    edges.any(
      (e) =>
          (e.to == b.id && f.inPort != null && e.toPort == f.inPort) ||
          (e.from == b.id && f.sends(e.fromPort)),
    );

/// Whether [f] is a row of [b] on the canvas (spec §12 Pins, owner decision
/// 2026-11-09): a bound field always; else what the user chose for this
/// block ([FlowBlock.pins]); else the type's default ([FlowField.onBlock]).
/// The inspector lists every field, pinned or not.
bool fieldPinned(FlowBlock b, FlowField f, Iterable<FlowEdge> edges) =>
    fieldBound(b, f, edges) || (b.pins[f.id] ?? f.onBlock);

/// The rows of [b] drawn on the canvas: its pinned fields ([fieldPinned]),
/// in the order of [fieldsOf].
List<FlowField> rowsOf(
  NodeType? t,
  FlowBlock b, {
  Iterable<FlowEdge> edges = const [],
}) => [
  for (final f in fieldsOf(t, b, edges: edges))
    if (fieldPinned(b, f, edges)) f,
];

/// The height the editor draws [b] at: header 32, body padding 6 + 8, 28
/// per row, and the − / + row of a variable block.
double blockHeight(
  NodeType? t,
  FlowBlock b, {
  Iterable<FlowEdge> edges = const [],
}) {
  final rows = rowsOf(t, b, edges: edges).length;
  final tools = variadicOf(t, b) == null ? 0.0 : 38.0;
  // An instance has one more row: `Open inside`.
  final link = isInstance(b.type) ? 28.0 : 0.0;
  return 32 + 6 + 28.0 * math.max(rows, 1) + link + 8 + tools;
}

// ---------- binding (drag a field onto another, spec §4) ----------

/// Why a field does not take a binding from the field being dragged.
enum BindRefusal {
  /// The target is an output: it takes nothing.
  output,

  /// The target is a parameter the engine has no `in.<p>` port for
  /// (`scale` `k`): it is typed in the inspector.
  noInput,

  /// The source is a field of the same block.
  self,

  /// The two port types do not fit (`number` into `bool`).
  type,

  /// The edge would close a loop that no `delay` breaks (validation step 5).
  loop,

  /// The field takes a wire only on a broker with ADR 0040 (a key from a
  /// port, an argument's port): this one's catalog has no port for it.
  needsBroker,
}

/// A refusal and, for [BindRefusal.type], the two types.
final class Refused {
  const Refused(this.reason, {this.from = '', this.to = ''});

  final BindRefusal reason;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is Refused &&
      other.reason == reason &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(reason, from, to);

  @override
  String toString() => 'Refused($reason $from $to)';
}

/// The type the engine gives output [port] of a block of type [t]
/// (`number`, `bool`, `map`, `any`): the catalog's `port_types`, else a
/// parameter's echo by the parameter's type (ADR 0038 §6), else `any`.
String outputType(NodeType? t, String port) {
  if (t == null) {
    return 'any';
  }
  final listed = t.portTypes[port];
  if (listed != null) {
    return listed;
  }
  final p = t.params.where((p) => p.name == port).firstOrNull;
  return switch (p?.type) {
    'number' || 'int' => 'number',
    'bool' => 'bool',
    'map' => 'map',
    _ => 'any',
  };
}

/// The type the engine gives input [port] (`port_types`, else `any`).
String inputType(NodeType? t, String port) => t?.portTypes[port] ?? 'any';

/// Whether `fromBlock.fromPort` may be bound into the field [to] of
/// `toBlock` (spec §4); null when it may. [replacing] is an edge being
/// moved (a wire picked up from its input): it is left out of the loop
/// check, as is the edge already into [to].
Refused? bindRefusal(
  Map<String, NodeType> types,
  FlowDraft d, {
  required String fromBlock,
  required String fromPort,
  required String toBlock,
  required FlowField to,
  (String, String)? replacing,
}) {
  final inPort = to.inPort;
  if (inPort == null) {
    final dstType = d.blocks[toBlock]?.type;
    final later =
        to.kind == FieldKind.arg ||
        to.kind == FieldKind.param &&
            const {'key', 'path'}.contains(to.name) &&
            const {
              'subscribe',
              'liveliness',
              'load_value',
              'list_children',
              'load_history',
              'get_node',
            }.contains(dstType);
    return Refused(
      to.kind == FieldKind.output
          ? BindRefusal.output
          : (later ? BindRefusal.needsBroker : BindRefusal.noInput),
    );
  }
  if (fromBlock == toBlock) {
    return const Refused(BindRefusal.self);
  }
  final src = d.blocks[fromBlock];
  final dst = d.blocks[toBlock];
  final ft = outputType(types[src?.type], fromPort);
  final tt = inputType(types[dst?.type], inPort);
  if (ft != tt && ft != 'any' && tt != 'any') {
    return Refused(BindRefusal.type, from: ft, to: tt);
  }
  // A loop: does the target already reach the source? Edges into a delay
  // do not count (the engine's step 5).
  if (dst?.type != 'delay') {
    final next = <String, List<String>>{};
    for (final e in d.edges) {
      if ((e.to == toBlock && e.toPort == inPort) ||
          (replacing != null &&
              e.to == replacing.$1 &&
              e.toPort == replacing.$2) ||
          d.blocks[e.to]?.type == 'delay') {
        continue;
      }
      next.putIfAbsent(e.from, () => []).add(e.to);
    }
    final seen = <String>{};
    final todo = [toBlock];
    while (todo.isNotEmpty) {
      final n = todo.removeLast();
      if (n == fromBlock) {
        return const Refused(BindRefusal.loop);
      }
      if (seen.add(n)) {
        todo.addAll(next[n] ?? const []);
      }
    }
  }
  return null;
}

/// The key of a live value of [node] in `flowEditor.ports`.
String portKey(String dir, String node, String port) => '$dir:$node.$port';

/// What a field shows.
final class FieldValue {
  const FieldValue(
    this.text, {
    this.bound = false,
    this.bad = false,
    this.live = false,
    this.raw,
    this.quality,
  });

  final String text;

  /// The value itself, as [text] reads it in short: a map or a list whole,
  /// for the field's viewer.
  final Object? raw;

  /// The quality of the sample behind it; null for a typed value.
  final Quality? quality;

  /// An edge feeds it: the binding wins over the typed value.
  final bool bound;

  /// Its quality is bad.
  final bool bad;

  /// It is a sample (live), not a typed value.
  final bool live;
}

/// The value [f] of block [b] shows (spec §3, owner decision 2026-11-08):
/// a bound field the value that comes in along its wire, never the path;
/// an unbound parameter its typed value or default; an input or an output
/// its last sample; a variable's `Value` what it sends (`out`), else what
/// came in, else its typed value. [live] reads the live values (keys of
/// [portKey]); the editor's [live] also follows a wire of the draft back
/// to its source when the input has no sample of its own. A bound field
/// with nothing known shows nothing rather than a typed value that the
/// binding replaces. A sample of a point reads with its [unit] and
/// [choices].
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
      if (f.variable) {
        sample =
            live(portKey('out', b.id, f.outPort!)) ??
            (bound ? live(portKey('in', b.id, f.inPort!)) : null);
        shown =
            sample?.value ??
            (bound
                ? null
                : typed ?? live(portKey('param', b.id, p.name))?.value);
      } else if (bound) {
        sample =
            live(portKey('in', b.id, f.inPort!)) ??
            live(portKey('param', b.id, p.name));
        shown = sample?.value;
      } else {
        shown = typed ?? live(portKey('param', b.id, p.name))?.value;
      }
      if (sample == null && shown == null) {
        return FieldValue('', bound: bound);
      }
    case FieldKind.input:
      // An operand's typed constant, until a binding replaces it (ADR 0038
      // §7): bound, the value that comes in; else the constant.
      final constant = f.operand && !bound
          ? operandValueOf(b, f.inPort!)
          : null;
      if (constant != null) {
        shown = constant;
        break;
      }
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
      // An argument's constant, until a binding replaces it (ADR 0040 §2).
      if (bound) {
        sample = live(portKey('in', b.id, f.inPort!));
        shown = sample?.value;
        if (sample == null) {
          return FieldValue('', bound: bound);
        }
      } else {
        shown = (b.cfg['args'] as Map?)?[f.name];
      }
  }
  final point = f.kind == FieldKind.input || f.kind == FieldKind.output;
  return FieldValue(
    switch (shown) {
      final Map<Object?, Object?> m when m.isNotEmpty => '{…}',
      final List<Object?> l when l.isNotEmpty => '[…]',
      // A date of the engine (µs) reads as a date and time.
      final num n when isTimeField(b.type, f.name) && dateText(n) != null =>
        dateText(n)!,
      _ when point && sample != null => valueText(
        shown,
        unit: unit,
        choices: choices,
      ),
      _ => valueText(shown),
    },
    bound: bound,
    bad: sample?.quality == Quality.bad,
    live: sample != null,
    raw: shown,
    quality: sample?.quality,
  );
}
