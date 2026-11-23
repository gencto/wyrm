import 'dart:math' as math;

import 'package:models/block_category.dart';
import 'package:models/block_type.dart';
import 'package:models/engine_port.dart';
import 'package:models/field_id.dart';
import 'package:models/field_label.dart';
import 'package:models/field_word.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/port_end.dart';
import 'package:models/port_side.dart';
import 'package:models/port_type.dart';
import 'package:models/quality.dart';
import 'package:wyrm_client/wyrm_client.dart' show TypeCode;

import '../decode/flow_rows.dart';
import '../decode/live_values.dart';
import '../labels.dart';
import 'block_cfg.dart';
import 'config_text.dart';
import 'flow_blocks.dart';
import 'flow_mapper.dart';
import 'value_text.dart';

export 'package:models/block_category.dart';
export 'package:models/block_cfg_key.dart';
export 'package:models/engine_port.dart';
export 'package:models/field_id.dart' show FieldKind;
export 'package:models/port_side.dart';

export '../decode/flow_rows.dart' show portKey;
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
const Set<KnownBlock> _reads = {KnownBlock.subscribe, KnownBlock.liveliness};

/// Types whose point is their `key`; the others name it `path`.
const Set<KnownBlock> _keyed = {
  KnownBlock.subscribe,
  KnownBlock.liveliness,
  KnownBlock.loadValue,
  KnownBlock.loadHistory,
  KnownBlock.getNode,
};
const Set<KnownBlock> _sinks = {
  KnownBlock.publish,
  KnownBlock.set,
  KnownBlock.invoke,
};

/// Inputs into these write to a device (ember wires, spec §4).
const Set<KnownBlock> writingTypes = {KnownBlock.set, KnownBlock.invoke};

/// Whether inputs into a block of [type] write to a device.
bool writesTo(BlockType? type) => writingTypes.contains(type?.known);

/// Block types that read from the tree (IN, teal, in the palette).
const Set<KnownBlock> sourceTypes = {
  KnownBlock.subscribe,
  KnownBlock.liveliness,
  KnownBlock.loadValue,
  KnownBlock.listChildren,
  KnownBlock.loadHistory,
  KnownBlock.getNode,
  KnownBlock.timer,
  KnownBlock.history,
  KnownBlock.dql,
  KnownBlock.const_,
};

/// Whether a block of [type] reads from the tree.
bool isSource(BlockType type) => sourceTypes.contains(type.known);

/// Whether a block of [type] writes to the tree (OUT, ember, in the
/// palette): `set`, `invoke`, `publish`. Everything between is logic.
bool isSink(BlockType type) => _sinks.contains(type.known);

/// The block types that stand for one point of the tree: its value is
/// theirs.
const Set<KnownBlock> pointTypes = {
  KnownBlock.subscribe,
  KnownBlock.liveliness,
  KnownBlock.set,
  KnownBlock.publish,
};

/// Whether a block of [type] stands for one point of the tree.
bool isPoint(BlockType type) => pointTypes.contains(type.known);

/// The role of a block of [type].
BlockRole roleOf(BlockType type) => switch (type) {
  CustomType() || BoundaryType() => BlockRole.custom,
  EngineType(
    known: KnownBlock.subscribe || KnownBlock.liveliness || KnownBlock.set,
  ) =>
    BlockRole.node,
  EngineType(known: KnownBlock.publish) => BlockRole.sink,
  EngineType(known: KnownBlock.invoke) => BlockRole.action,
  EngineType() => BlockRole.logic,
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
    switch (_keyed.contains(b.type.known) ? b.cfgKey : b.cfgPath) {
      final k? when k.isNotEmpty => k,
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
    this.port,
  });

  /// Unique within the block: its kind and the engine's name for it.
  final FieldId id;

  /// What the engine calls it: the parameter (`input_min`), the port
  /// (`in`, `in.0`, `quotient`) or the argument; shown small in the
  /// inspector and in the row's tooltip.
  final String name;

  /// What the row reads: [fieldLabel] (`Input min`, `Input 1`, `Output`),
  /// a point's own name, an argument's key; never `in.<p>`, no colon.
  final FieldLabel label;
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

  /// The engine port an input or an output field is, when the catalog
  /// names it as one the editor treats in its own way
  /// ([NodeType.knownInputs], [NodeType.knownOutputs]); null for any other
  /// field.
  final EnginePort? port;

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
      other.port == port &&
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
  final names = b.namesOf(param) ?? t.dynInDefaults.toList();
  final step = pairedInputs.contains(b.type.known) ? 2 : 1;
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
FieldLabel caseLabel(String name) => switch (int.tryParse(name)) {
  final n? => FieldLabel.numbered(FieldWord.caseOf, n + 1),
  null => FieldLabel.text(name),
};

/// Block types whose variable inputs come in pairs: `case` (a case value,
/// then what it gives; ADR 0038 §8).
const Set<KnownBlock> pairedInputs = {KnownBlock.case_};

/// What the variable input at [index] of a paired block reads: `Case 1`,
/// `Then 1`, `Case 2`, … (flow-editor.md §3: labels by position, as the
/// engine reads the pairs by position).
FieldLabel pairLabel(int index) => FieldLabel.numbered(
  index.isEven ? FieldWord.caseOf : FieldWord.then,
  index ~/ 2 + 1,
);

// ---------- labels (flow-editor.md §3, owner decision 2026-11-08) ----------

/// Ports whose sentence-case name reads wrong or says too little.
const portLabels = <EnginePort, FieldWord>{
  EnginePort.in_: FieldWord.input,
  EnginePort.out: FieldWord.output,
  EnginePort.trigger: FieldWord.trigger,
  EnginePort.inputOutOfRange: FieldWord.inputOutOfRange,
};

/// Parameters whose sentence-case name reads wrong or says too little.
/// [typedFieldLabels] names a parameter of one type and wins over these.
const paramLabels = <BlockCfgKey, FieldWord>{
  BlockCfgKey.k: FieldWord.factor,
  BlockCfgKey.b: FieldWord.offset,
  BlockCfgKey.abs: FieldWord.absoluteChange,
  BlockCfgKey.pct: FieldWord.percentChange,
  BlockCfgKey.fn: FieldWord.function,
  BlockCfgKey.op: FieldWord.operation,
  BlockCfgKey.expr: FieldWord.expression,
  BlockCfgKey.msg: FieldWord.message,
  BlockCfgKey.ms: FieldWord.delayMs,
  BlockCfgKey.key: FieldWord.point,
  BlockCfgKey.node: FieldWord.valueName,
  BlockCfgKey.meta: FieldWord.meta,
  BlockCfgKey.allowBad: FieldWord.allowBadQuality,
  BlockCfgKey.onBad: FieldWord.onBadQuality,
  BlockCfgKey.maxSamples: FieldWord.maxSamples,
  BlockCfgKey.memoryMb: FieldWord.memoryMb,
  // ADR 0040: behaviours, scopes, the second set of blocks.
  BlockCfgKey.trigger: FieldWord.trigger,
  BlockCfgKey.intervalMs: FieldWord.every,
  BlockCfgKey.autoRun: FieldWord.autoRun,
  BlockCfgKey.runOnStart: FieldWord.runOnStart,
  BlockCfgKey.keyScope: FieldWord.scope,
  BlockCfgKey.pathScope: FieldWord.scope,
};

/// The label of a parameter of one type: it wins over [paramLabels]
/// (`latch` has an input and a parameter both named `reset`).
const typedFieldLabels = <KnownBlock, Map<BlockCfgKey, FieldWord>>{
  KnownBlock.latch: {BlockCfgKey.reset: FieldWord.resetMode},
  // A liveliness token belongs to a node, not to a point.
  KnownBlock.liveliness: {BlockCfgKey.key: FieldWord.node},
  KnownBlock.set: {
    BlockCfgKey.path: FieldWord.point,
    BlockCfgKey.on: FieldWord.writeOn,
  },
  KnownBlock.invoke: {
    BlockCfgKey.path: FieldWord.node,
    BlockCfgKey.on: FieldWord.runOn,
  },
  KnownBlock.stopwatch: {BlockCfgKey.interval: FieldWord.intervalS},
  // ADR 0040: the second set of blocks.
  KnownBlock.listChildren: {BlockCfgKey.path: FieldWord.node},
  KnownBlock.throttle: {BlockCfgKey.ms: FieldWord.periodMs},
  KnownBlock.debounce: {BlockCfgKey.ms: FieldWord.quietTimeMs},
  // ADR 0044: the third set (docs/flow-blocks.md, the editor's table).
  KnownBlock.getNode: {BlockCfgKey.key: FieldWord.node},
  KnownBlock.dateRange: {BlockCfgKey.rangeDelimiter: FieldWord.delimiter},
};

/// Inputs that are commands, not values: a sample on the wire presses them
/// (docs/flow-blocks.md: `date_range` moves to the next or the previous
/// range, `table_page` to a page). The editor draws them as buttons.
const commandInputs = <KnownBlock, Set<EnginePort>>{
  KnownBlock.dateRange: {EnginePort.next, EnginePort.previous},
  KnownBlock.tablePage: {
    EnginePort.next,
    EnginePort.previous,
    EnginePort.first,
    EnginePort.last,
  },
};

/// The ports that hold a date: microseconds since the Unix epoch (ADR 0044
/// §3). The editor shows such a value as a date and time; the viewer adds
/// the instant in UTC and the number. `date_range.duration` is a length of
/// time, not a date.
const timeFields = <KnownBlock, Set<EnginePort>>{
  KnownBlock.now: {EnginePort.out},
  KnownBlock.dateTime: {EnginePort.out},
  KnownBlock.dateParse: {EnginePort.in_, EnginePort.time},
  KnownBlock.dateFormat: {EnginePort.in_},
  KnownBlock.dateMath: {EnginePort.in_, EnginePort.out},
  KnownBlock.dateRange: {EnginePort.start, EnginePort.end},
};

/// Whether the field at engine port [port] of a block of [type] holds a
/// date ([timeFields]).
bool isTimeField(BlockType type, EnginePort? port) =>
    timeFields[type.known]?.contains(port) ?? false;

/// The time zone parameters of the date blocks (ADR 0044 §3): an IANA name,
/// `UTC` or `±HH:MM`; `date_format` also takes `auto`.
bool isTimeZoneParam(BlockType type, ParamSpec p) =>
    p.key == BlockCfgKey.timeZone &&
    const {
      KnownBlock.dateTime,
      KnownBlock.dateFormat,
      KnownBlock.dateParse,
      KnownBlock.dateMath,
      KnownBlock.dateRange,
      KnownBlock.loadHistory,
      KnownBlock.tableRollup,
    }.contains(type.known);

/// The fields that hold a range text as `date_range` reads it (`today`,
/// `lastWeek`, `current24hours`, `2026-10`, `<a>/<b>`): the operand `in`
/// of `date_range` ([port]) and the parameter `time_range` of
/// `load_history` ([param]).
bool isRangeText(BlockType type, {EnginePort? port, BlockCfgKey? param}) =>
    switch (type.known) {
      KnownBlock.dateRange => port == EnginePort.in_,
      KnownBlock.loadHistory => param == BlockCfgKey.timeRange,
      _ => false,
    };

/// Operands that the engine reads as a text only: a typed value stays the
/// text it is (a CSV `1,2` or `5`, a JSON text), never the number or the
/// list JSON would make of it. Such a text may hold several lines (the
/// value viewer's Edit, flow-blocks.md "What calculates at start").
const textOperands = <KnownBlock, Set<EnginePort>>{
  KnownBlock.tableFromCsv: {EnginePort.in_},
  KnownBlock.split: {EnginePort.in_},
  KnownBlock.replace: {EnginePort.in_},
  KnownBlock.jsonParse: {EnginePort.in_},
};

/// Whether the operand at engine port [port] of a block of [type] is a
/// text ([textOperands]).
bool isTextOperand(BlockType type, EnginePort? port) =>
    textOperands[type.known]?.contains(port) ?? false;

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
List<String> timeZoneChoicesOf(BlockType type) => [
  if (type.known == KnownBlock.dateFormat) 'auto',
  ...timeZoneChoices,
];

/// Whether field [f] of a block of type [t] may hold a table given as a
/// list of maps (ADR 0044 §2): the table inputs and outputs of the Tables
/// blocks, the rows a reader gives (`list_children`, `load_history`) and
/// the actions of `get_node`. A value `{columns, rows}` is a table
/// anywhere.
bool holdsTable(NodeType? t, FlowField f) =>
    switch ((t?.type.known, f.port, f.spec?.key)) {
      (
        KnownBlock.listChildren || KnownBlock.loadHistory,
        EnginePort.out,
        _,
      ) =>
        true,
      (KnownBlock.getNode, EnginePort.actions, _) => true,
      // The `table` variable: its Value (parameter `value`), its ports.
      (KnownBlock.table, EnginePort.out || EnginePort.in_, _) ||
      (KnownBlock.table, _, BlockCfgKey.value) => true,
      (_, EnginePort.in_ || EnginePort.right || EnginePort.out, _) =>
        t?.knownCategory == BlockCategory.tables,
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
List<ListColumn>? listItemsOf(NodeType? t, ParamSpec p) {
  switch ((t?.type.known, p.key)) {
    case (KnownBlock.tableMapColumns, BlockCfgKey.mapping):
      return const [ListColumn('name'), ListColumn('from')];
    case (
      KnownBlock.tableGroupBy || KnownBlock.tableRollup,
      BlockCfgKey.aggregates,
    ):
      final listed = t?.params
          .where((p) => p.key == BlockCfgKey.method)
          .firstOrNull
          ?.choices;
      return [
        const ListColumn('column'),
        ListColumn(
          'method',
          choices: listed == null || listed.isEmpty
              ? aggregateMethods
              : listed.unlock,
        ),
        const ListColumn('as'),
      ];
    default:
      return null;
  }
}

/// One key of the items of a list parameter ([listItemsOf]): the key each
/// item map holds (`column`, `method`) and, for a choice, its choices.
final class ListColumn {
  const ListColumn(this.key, {this.choices = const []});

  /// The key in each item's map, as the engine reads it.
  final String key;

  /// The values it takes; empty: any text.
  final List<String> choices;

  @override
  bool operator ==(Object other) =>
      other is ListColumn &&
      other.key == key &&
      other.choices.length == choices.length &&
      [
        for (var i = 0; i < choices.length; i++) other.choices[i] == choices[i],
      ].every((x) => x);

  @override
  int get hashCode => Object.hash(key, Object.hashAll(choices));
}

/// The items of a list parameter as rows of texts by key ([listItemsOf]):
/// a text as it is, another value as JSON. A value that is no list of maps
/// gives no rows.
List<Map<String, String>> listRowsOf(JsonValue v) => listRowsIn(v);

/// Whether the input at engine port [port] of a block of [type] is a
/// command ([commandInputs]).
bool isCommandInput(BlockType type, EnginePort? port) =>
    commandInputs[type.known]?.contains(port) ?? false;

/// [types] in the palette's order: by [BlockCategory], the catalog's
/// order within a category.
List<NodeType> inPaletteOrder(Iterable<NodeType> types) {
  final seen = <String>[];
  for (final t in types) {
    if (!seen.contains(t.category)) {
      seen.add(t.category);
    }
  }
  int rank(NodeType t) =>
      t.knownCategory?.index ??
      BlockCategory.values.length + seen.indexOf(t.category);

  final all = types.toList();
  final at = <BlockType, int>{for (final (i, t) in all.indexed) t.type: i};
  return all..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : at[a.type]!.compareTo(at[b.type]!);
  });
}

/// What a block type reads in the palette and in a block's header: the
/// engine's name in sentence case (`rising_edge` → `Rising edge`,
/// `list_children` → `List children`); a custom block keeps the name its
/// author gave it.
String blockLabel(BlockType type) => switch (type) {
  CustomType(:final name) => name,
  EngineType(known: KnownBlock.wasm) => 'WASM',
  _ => humanize(type.wire),
};

/// The fields that say when a command or a read runs (ADR 0040 §2).
const behaviourParams = <BlockCfgKey>{
  BlockCfgKey.intervalMs,
  BlockCfgKey.autoRun,
  BlockCfgKey.enabled,
  BlockCfgKey.runOnStart,
};

/// Whether blocks of [t] have behaviours: a `trigger` input and the event
/// outputs (`invoke`, `set`, `load_value`, `list_children` since ADR 0040).
bool behavesOf(NodeType? t) =>
    t != null &&
    t.knownInputs.containsValue(EnginePort.trigger) &&
    t.knownOutputs.containsValue(EnginePort.lastRun);

/// The inspector's groups of a block with behaviours (flow-editor.md §19).
enum FieldGroup { none, target, arguments, behaviour, events, state }

/// The behaviour inputs in the order the inspector lists them: before
/// the parameters ([_behaviourParamOrder]).
const _behaviourInputOrder = <EnginePort>[EnginePort.trigger, EnginePort.in_];

/// The behaviour parameters in the order the inspector lists them.
const _behaviourParamOrder = <BlockCfgKey>[
  BlockCfgKey.autoRun,
  BlockCfgKey.intervalMs,
  BlockCfgKey.enabled,
  BlockCfgKey.runOnStart,
  BlockCfgKey.on,
  BlockCfgKey.deadband,
  BlockCfgKey.allowBad,
];

/// Where [f] stands among a block's behaviours; after them all when it is
/// none.
int _behaviourRank(FlowField f) {
  final param = f.kind == FieldKind.param ? f.spec?.key : null;
  final i = param != null
      ? _behaviourParamOrder.indexOf(param)
      : switch ((f.kind, f.port)) {
          (FieldKind.input, final port?) => _behaviourInputOrder.indexOf(port),
          _ => -1,
        };
  if (i < 0) {
    return _behaviourInputOrder.length + _behaviourParamOrder.length;
  }
  return param != null ? _behaviourInputOrder.length + i : i;
}

/// The group field [f] of [b] is listed under; [FieldGroup.none] for a
/// type without behaviours.
FieldGroup groupOf(NodeType? t, FlowBlock b, FlowField f) {
  if (!behavesOf(t)) {
    return FieldGroup.none;
  }
  return switch (f.kind) {
    FieldKind.arg => FieldGroup.arguments,
    FieldKind.param =>
      _behaviourParamOrder.contains(f.spec?.key)
          ? FieldGroup.behaviour
          : FieldGroup.target,
    FieldKind.input =>
      f.port == EnginePort.in_ && b.type.known == KnownBlock.set
          ? FieldGroup.target
          : FieldGroup.behaviour,
    FieldKind.output => switch (f.port) {
      EnginePort.sent || EnginePort.ok || EnginePort.error => FieldGroup.events,
      _ => FieldGroup.state,
    },
  };
}

/// Outputs that say more under their own name than as `Output`.
const outputLabelOverrides = <KnownBlock, Map<EnginePort, FieldWord>>{
  // A presence, not a value (docs/flow-blocks.md, "A key from a port").
  KnownBlock.liveliness: {EnginePort.out: FieldWord.alive},
  KnownBlock.invoke: {EnginePort.out: FieldWord.result},
  KnownBlock.stats: {EnginePort.avg: FieldWord.average},
  KnownBlock.alarm: {EnginePort.out: FieldWord.active},
  KnownBlock.timer: {EnginePort.out: FieldWord.count},
  KnownBlock.constant: {EnginePort.out: FieldWord.value},
};

/// Parameters a block of a type lists in the inspector only, though they
/// have a port or a default (docs/flow-blocks.md, the editor's table): the
/// rows that crowd the block and that few flows set. A wire or the user's
/// pin still puts them on the block.
const inspectorOnly = <KnownBlock, Set<BlockCfgKey>>{
  KnownBlock.loadHistory: {BlockCfgKey.limit, BlockCfgKey.timeZone},
  KnownBlock.tableFilter: {BlockCfgKey.expr},
  KnownBlock.tableRemoveRows: {BlockCfgKey.expr},
  KnownBlock.tableEditRows: {BlockCfgKey.expr},
};

/// Parameters of which the engine needs one or the other: both are rows
/// of the block, though neither has a default.
const _oneOf = <KnownBlock, Set<BlockCfgKey>>{
  KnownBlock.deadband: {BlockCfgKey.abs, BlockCfgKey.pct},
  KnownBlock.alarm: {BlockCfgKey.high, BlockCfgKey.low},
};

/// What a field named [name] of a block of [type] reads in Studio: the
/// catalog's own `display`, else an override by its parameter [spec]
/// ([typedFieldLabels], [paramLabels]) or its engine [port]
/// ([portLabels]), else [humanize]. Numbered inputs (`in.0`) read
/// `Input 1`; other variable inputs keep the name the user gave them (an
/// `expression` variable, a `wasm` port).
FieldLabel fieldLabel(
  BlockType type,
  String name, {
  ParamSpec? spec,
  EnginePort? port,
  bool variable = false,
}) {
  final display = spec?.display;
  if (display != null && display.isNotEmpty) {
    return FieldLabel.text(display);
  }
  final short = paramOfPort(name) ?? name;
  if (variable) {
    final n = int.tryParse(short);
    return n == null
        ? FieldLabel.text(short)
        : FieldLabel.numbered(FieldWord.input, n + 1);
  }
  final key = spec?.key;
  final word =
      (key == null ? null : typedFieldLabels[type.known]?[key]) ??
      (key == null ? null : paramLabels[key]) ??
      (port == null ? null : portLabels[port]);
  return word == null
      ? FieldLabel.text(humanize(short))
      : FieldLabel.word(word);
}

/// What the output [p] (engine [port]) of a block of [type] reads. A
/// `subscribe` output ([reads]) is its point's value, named after the
/// point ([pointName]); a `liveliness` output is whether its node is
/// there; a port its author [named] keeps that name; an `invoke` that
/// [behaves] reads `Output`; else an override, else [fieldLabel].
FieldLabel _outputLabel(
  BlockType type,
  String p,
  EnginePort? port, {
  required String? pointName,
  required bool reads,
  required bool named,
  required bool behaves,
}) {
  final word = outputLabelOverrides[type.known]?[port];
  final own = word == null ? null : FieldLabel.word(word);
  final plain = fieldLabel(type, p, port: port);
  if (reads && port == EnginePort.out) {
    return own ?? (pointName == null ? plain : FieldLabel.text(pointName));
  }
  if (named) {
    return FieldLabel.text(p);
  }
  return type.known == KnownBlock.invoke && port == EnginePort.out && behaves
      ? plain
      : own ?? plain;
}

// ---------- forms (a block that does one of two things) ----------

/// The forms a block may have (ADR 0032 §7: `scale`).
enum BlockFormId {
  /// `k × in + b`.
  linear,

  /// A map from an input range to an output range.
  range,
}

/// One way a block of a type works, with the fields only it uses (ADR 0032
/// §7: `scale` is `k × in + b`, or a range map). The editor shows one form
/// at a time; the first is the default and needs nothing in the config.
final class BlockForm {
  const BlockForm(
    this.id, {
    this.params = const {},
    this.outputs = const {},
    this.defaults = const {},
  });

  /// Which form it is (the inspector words it).
  final BlockFormId id;

  /// The parameters only this form uses (with their `in.<p>` ports and
  /// echo outputs).
  final Set<BlockCfgKey> params;

  /// The outputs only this form sends.
  final Set<EnginePort> outputs;

  /// The engine's defaults of [params], for a catalog that does not give
  /// them (before ADR 0038).
  final Map<BlockCfgKey, Object> defaults;
}

const _forms = <KnownBlock, List<BlockForm>>{
  KnownBlock.scale: [
    BlockForm(BlockFormId.linear, params: {BlockCfgKey.k, BlockCfgKey.b}),
    BlockForm(
      BlockFormId.range,
      params: {
        BlockCfgKey.inputMin,
        BlockCfgKey.inputMax,
        BlockCfgKey.outputMin,
        BlockCfgKey.outputMax,
      },
      outputs: {EnginePort.inputOutOfRange},
      defaults: {
        BlockCfgKey.inputMin: 0,
        BlockCfgKey.inputMax: 1,
        BlockCfgKey.outputMin: 0,
        BlockCfgKey.outputMax: 100,
      },
    ),
  ],
};

/// The forms of a block of [type]; empty for a type with one.
List<BlockForm> formsOf(BlockType type) => _forms[type.known] ?? const [];

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
          b.hasParam(p.wire) ||
          edges.any((e) => e.to == b.id && e.target.paramKey == p),
    );
    if (given) {
      return f;
    }
  }
  return forms.first;
}

/// Whether the parameter [param] of [b] belongs to a form [b] is not in,
/// and nothing keeps it: neither the config nor an edge into its port or
/// out of its echo. Such a field is not shown.
bool _otherFormParam(
  FlowBlock b,
  BlockCfgKey? param,
  Iterable<FlowEdge> edges,
) {
  if (param == null ||
      !_inOtherForm(b, edges, (f) => f.params.contains(param))) {
    return false;
  }
  final kept =
      b.hasParam(param.wire) ||
      edges.any(
        (e) =>
            (e.to == b.id && e.target.paramKey == param) ||
            (e.from == b.id && e.source.echoKey == param),
      );
  return !kept;
}

/// Whether the output [port] of [b] belongs to a form [b] is not in, and
/// no edge leaves it. Such a field is not shown.
bool _otherFormOutput(
  FlowBlock b,
  EnginePort? port,
  Iterable<FlowEdge> edges,
) {
  if (port == null ||
      !_inOtherForm(b, edges, (f) => f.outputs.contains(port))) {
    return false;
  }
  return !edges.any((e) => e.from == b.id && e.source.known == port);
}

/// Whether what [owns] tests belongs to a form of [b] that [b] is not in.
bool _inOtherForm(
  FlowBlock b,
  Iterable<FlowEdge> edges,
  bool Function(BlockForm) owns,
) {
  final form = formOf(b, edges);
  if (form == null || owns(form)) {
    return false;
  }
  return formsOf(b.type).any(owns);
}

// ---------- the fields of a block ----------

/// The input port parameter [name] of [t] has when the catalog names no
/// `port` (before ADR 0038): `in.<name>` when the type lists it.
String? _inputOfParam(NodeType t, String name) {
  final port = PortEnd.inputOf(name);
  return t.inputs.contains(port) ? port : null;
}

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
        id: FieldId.input('in'),
        name: 'in',
        label: FieldLabel.word(FieldWord.input),
        kind: .input,
        inPort: 'in',
      ),
      FlowField(
        id: FieldId.output('out'),
        name: 'out',
        label: FieldLabel.word(FieldWord.output),
        kind: .output,
        outPort: 'out',
      ),
    ];
  }
  // A variable (`number`, `string`, `bool`, `const`): its input, its
  // parameter and its output are one field (spec §3).
  if (isVariable(t)) {
    final p = t.params.first;
    final mainIn = mainInputOf(t);
    return [
      FlowField(
        id: FieldId.param(p.name),
        name: p.name,
        label: fieldLabel(b.type, p.name, spec: p),
        kind: .param,
        spec: p,
        inPort: mainIn,
        outPort: EnginePort.out.wire,
        outAliases: [
          if (p.echo ?? true) p.name,
          if (mainIn != null && (t.echoInputs ?? true)) mainIn,
        ],
        variable: true,
      ),
    ];
  }
  final role = roleOf(b.type);
  final ports = portsOf(t, b);
  final sink = _sinks.contains(b.type.known);
  final known = b.type.known;
  final echoInputs = !sink && (t.echoInputs ?? true);
  final dynParams = {?t.dynInParam, ?t.dynOutParam};

  // Which parameter owns which input port.
  final portOf = <String, String>{};
  for (final p in t.params) {
    final port = p.port ?? _inputOfParam(t, p.name);
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
  final instance = b.type is CustomType;
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
        (known == KnownBlock.set &&
            t.knownInputs[port] == EnginePort.in_ &&
            (t.echoInputs ?? true));
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
      if (!dynParams.contains(p.name) && !_otherFormParam(b, p.key, edges))
        FlowField(
          id: FieldId.param(p.name),
          name: p.name,
          label: fieldLabel(b.type, p.name, spec: p),
          kind: .param,
          spec: p,
          inPort: portOf[p.name],
          // A scope is read on the block and typed in its prompt: it
          // feeds nothing.
          outPort: p.name == keyed?.scope ? null : paramEcho[p.name],
          onBlock: switch ((p.name, p.key)) {
            // The key takes a wire: it is a row with a left port.
            (final n, _) when n == keyed?.key => true,
            // Its scope shows once it matters: a wire feeds the key, or
            // a scope is written.
            (final n, _) when n == keyed?.scope => keyBound || b.hasParam(n),
            // Behaviours are set in the inspector; one that is set shows.
            (final n, final k) when behaves && behaviourParams.contains(k) =>
              b.hasParam(n),
            // The action block names its action in its header.
            (_, BlockCfgKey.action || BlockCfgKey.on)
                when behaves && role == BlockRole.action =>
              false,
            (_, final k) when inspectorOnly[known]?.contains(k) ?? false =>
              false,
            (_, final k) =>
              !node &&
                  !(role == BlockRole.action &&
                      const {
                        BlockCfgKey.path,
                        BlockCfgKey.args,
                        BlockCfgKey.allowBad,
                      }.contains(k)) &&
                  (portOf.containsKey(p.name) ||
                      (form?.params.contains(p.key) ?? false) ||
                      (_oneOf[known]?.contains(p.key) ?? false) ||
                      b.hasParam(p.name) ||
                      p.defaultValue != null ||
                      p.required),
          },
        ),
  ];
  FlowField input(String port, {required bool variable, int index = 0}) {
    final engine = t.knownInputs[port];
    final command = !variable && isCommandInput(b.type, engine);
    final name = port.startsWith(t.dynInPrefix)
        ? port.substring(t.dynInPrefix.length)
        : port;
    final main = engine == EnginePort.in_;
    return FlowField(
      id: FieldId.input(port),
      port: engine,
      name: port,
      label: switch (known) {
        KnownBlock.publish when main => const FieldLabel.word(FieldWord.value),
        KnownBlock.set when main => switch (pointName) {
          final name? => FieldLabel.text(name),
          null => const FieldLabel.word(FieldWord.input),
        },
        KnownBlock.invoke when main => const FieldLabel.word(
          FieldWord.runWhen,
        ),
        // A custom block's ports keep the names their author gave them.
        _ when instance => FieldLabel.text(port),
        _ when variable && pairedInputs.contains(known) => pairLabel(index),
        _ when variable && routed => caseLabel(name),
        _ => fieldLabel(b.type, port, port: engine, variable: variable),
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
          !(main && known == KnownBlock.invoke ||
              engine == EnginePort.trigger && node),
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
    if (known == KnownBlock.invoke) ...b.cfgArgs.keys,
  ];
  final argSpecs = {for (final p in actionParams) p.name: p};
  FlowField arg(String k, {required bool has}) => FlowField(
    id: FieldId.arg(k),
    name: k,
    label: FieldLabel.text(argSpecs[k]?.display ?? k),
    kind: .arg,
    inPort: t.dynInKeys ? '${t.dynInPrefix}$k' : null,
    argSpec: argSpecs[k],
    onBlock: has,
  );
  final args = <FlowField>[
    for (final k in argKeys) arg(k, has: true),
    if (known == KnownBlock.invoke)
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
      if (!_otherFormOutput(b, t.knownOutputs[p], edges) &&
          !caseOuts.contains(p))
        FlowField(
          id: FieldId.output(p),
          name: p,
          port: t.knownOutputs[p],
          // A `subscribe` output is its point's value, named after the
          // point; a `liveliness` output is whether its node is there.
          label: _outputLabel(
            b.type,
            p,
            t.knownOutputs[p],
            pointName: pointName,
            reads: _reads.contains(known),
            named: instance || t.dynOutParam != null && !t.outputs.contains(p),
            behaves: behaves,
          ),
          kind: .output,
          outPort: p,
          onBlock: switch (t.knownOutputs[p]) {
            // A refused key says why on `error`: a row once a wire feeds
            // the key.
            EnginePort.error when keyed != null && !behaves => keyBound,
            _ when !behaves => true,
            // A `set` is its point; its events are wired from the
            // inspector.
            _ when node => false,
            EnginePort.error => true,
            EnginePort.ok => known == KnownBlock.invoke,
            EnginePort.out => known != KnownBlock.invoke,
            _ => false,
          },
        ),
  ];
  // A sink names what it writes before the value it writes (`publish`:
  // node, value). Elsewhere the order is: operands, parameters, variable
  // inputs, then the trailing parameters ([tailParams]: `if` then, else;
  // `concat` strict), results.
  final tail = tailParams[known] ?? const <BlockCfgKey>{};
  final head = [
    for (final f in params)
      if (!tail.contains(f.spec?.key)) f,
  ];
  final after = [
    for (final f in params)
      if (tail.contains(f.spec?.key)) f,
  ];
  final all = role == BlockRole.sink
      ? [...params, ...fixed, ...dyn, ...args, ...outs]
      : [...fixed, ...head, ...dyn, ...after, ...args, ...outs];
  if (!behaves) {
    return all;
  }
  // A block with behaviours lists its fields by group (flow-editor.md
  // §19): what it acts on, its arguments, when it runs, what happened.
  final order = {for (final (i, f) in all.indexed) f.id: i};
  return all..sort((x, y) {
    final gx = groupOf(t, b, x);
    final gy = groupOf(t, b, y);
    if (gx != gy) {
      return gx.index.compareTo(gy.index);
    }
    final byRank = gx == FieldGroup.behaviour
        ? _behaviourRank(x).compareTo(_behaviourRank(y))
        : 0;
    return byRank != 0 ? byRank : order[x.id]!.compareTo(order[y.id]!);
  });
}

/// The trailing parameters: drawn after a block's variable inputs (order:
/// operands, parameters, variable inputs, then these, results). `if` reads
/// Operation · Input 1… · Then · Else · Output, `concat` Input 1… · Strict
/// · Output, `hub` Input 1… · Ignore null · Output · Index · On change.
const tailParams = <KnownBlock, Set<BlockCfgKey>>{
  KnownBlock.if_: {BlockCfgKey.then_, BlockCfgKey.else_},
  KnownBlock.concat: {BlockCfgKey.strict},
  KnownBlock.hub: {BlockCfgKey.ignoreNull},
  KnownBlock.case_: {BlockCfgKey.else_},
  // ADR 0044 (docs/flow-blocks.md, the editor's table).
  KnownBlock.router: {BlockCfgKey.singleOutput},
  KnownBlock.tableRecorder: {
    BlockCfgKey.enabled,
    BlockCfgKey.bufferSize,
    BlockCfgKey.timeWindowS,
    BlockCfgKey.ignoreNull,
  },
};

/// Whether blocks of [t] are variables: one parameter `value`, at most the
/// input `in`, the one output `out` (`number`, `string`, `bool`, `const`).
bool isVariable(NodeType? t) =>
    t != null &&
    t.params.length == 1 &&
    t.params.first.key == BlockCfgKey.value &&
    t.outputs.length == 1 &&
    t.knownOutputs[t.outputs.first] == EnginePort.out &&
    t.inputs.every((p) => t.knownInputs[p] == EnginePort.in_) &&
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
    fieldBound(b, f, edges) || (pinOf(b, f.id) ?? f.onBlock);

/// What the user chose for field [id] of [b] ([FlowBlock.pins], keyed by
/// [FieldId.key] as the definition's layout keeps it): pinned to the block,
/// taken off it, or null for the type's default.
bool? pinOf(FlowBlock b, FieldId id) => b.pins[id.key];

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
  final link = b.type is CustomType ? 28.0 : 0.0;
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
  const Refused(this.reason, {this.from, this.to});

  final BindRefusal reason;
  final PortType? from;
  final PortType? to;

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
PortType outputType(NodeType? t, String port) {
  if (t == null) {
    return PortType.any;
  }
  final listed = t.portTypes[port];
  if (listed != null) {
    return listed;
  }
  final p = t.params.where((p) => p.name == port).firstOrNull;
  return switch (p?.type) {
    TypeCode.number => PortType.number,
    TypeCode.bool_ => PortType.boolean,
    TypeCode.map => PortType.map,
    _ => PortType.any,
  };
}

/// The type the engine gives input [port] (`port_types`, else `any`).
PortType inputType(NodeType? t, String port) =>
    t?.portTypes[port] ?? PortType.any;

/// Whether `fromBlock.fromPort` may be bound into the field [to] of
/// `toBlock` (spec §4); null when it may. [replacing] is an edge being
/// moved (a wire picked up from its input): it is left out of the loop
/// check, as is the edge already into [to].
Refused? bindRefusal(
  Map<BlockType, NodeType> types,
  FlowDraft d, {
  required String fromBlock,
  required String fromPort,
  required String toBlock,
  required FlowField to,
  PortEnd? replacing,
}) {
  final inPort = to.inPort;
  if (inPort == null) {
    final dstType = d.blocks[toBlock]?.type.known;
    final later =
        to.kind == FieldKind.arg ||
        to.kind == FieldKind.param &&
            const {
              BlockCfgKey.key,
              BlockCfgKey.path,
            }.contains(to.spec?.key) &&
            const {
              KnownBlock.subscribe,
              KnownBlock.liveliness,
              KnownBlock.loadValue,
              KnownBlock.listChildren,
              KnownBlock.loadHistory,
              KnownBlock.getNode,
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
  if (!ft.fits(tt)) {
    return Refused(BindRefusal.type, from: ft, to: tt);
  }
  // A loop: does the target already reach the source? Edges into a delay
  // do not count (the engine's step 5).
  if (dst?.type.known != KnownBlock.delay) {
    final next = <String, List<String>>{};
    for (final e in d.edges) {
      if ((e.to == toBlock && e.toPort == inPort) ||
          e.target == replacing ||
          d.blocks[e.to]?.type.known == KnownBlock.delay) {
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

/// What a field shows.
final class FieldValue {
  const FieldValue(
    this.text, {
    this.bound = false,
    this.bad = false,
    this.live = false,
    this.raw,
    this.json,
    this.quality,
  });

  final String text;

  /// The value itself, as [text] reads it in short: a map or a list whole,
  /// for the field's viewer.
  final Object? raw;

  /// [raw] as JSON, decoded where it was read (a typed value as the config
  /// holds it, a sample by [liveJsonOf]); null when there is none or it is
  /// no JSON.
  final JsonValue? json;

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
  JsonValue? json;
  // What the field shows: a sample's value, or a typed one (as JSON).
  void showLive(LiveValue? s) {
    shown = s?.value;
    json = s == null ? null : liveJsonOf(s);
  }

  void showTyped(JsonValue v) {
    shown = v.raw;
    json = v;
  }

  switch (f.kind) {
    case FieldKind.param:
      final p = f.spec!;
      final typed = b.paramOr(p.name, p.defaultValue);
      LiveValue? param() => live(portKey(PortSide.param, b.id, p.name));
      if (f.variable) {
        sample =
            live(portKey(PortSide.output, b.id, f.outPort!)) ??
            (bound ? live(portKey(PortSide.input, b.id, f.inPort!)) : null);
        if (sample?.value != null) {
          showLive(sample);
        } else if (bound) {
          showLive(null);
        } else if (typed is! JsonNull) {
          showTyped(typed);
        } else {
          showLive(param());
        }
      } else if (bound) {
        sample =
            live(portKey(PortSide.input, b.id, f.inPort!)) ??
            live(portKey(PortSide.param, b.id, p.name));
        showLive(sample);
      } else if (typed is! JsonNull) {
        showTyped(typed);
      } else {
        showLive(param());
      }
      if (sample == null && shown == null) {
        return FieldValue('', bound: bound);
      }
    case FieldKind.input:
      // An operand's typed constant, until a binding replaces it (ADR 0038
      // §7): bound, the value that comes in; else the constant.
      final constant = f.operand && !bound
          ? operandValueOf(b, f.inPort!)
          : const JsonNull();
      if (constant is! JsonNull) {
        showTyped(constant);
        break;
      }
      sample = live(portKey(PortSide.input, b.id, f.inPort!));
      showLive(sample);
      if (sample == null) {
        return FieldValue('', bound: bound);
      }
    case FieldKind.output:
      sample = live(portKey(PortSide.output, b.id, f.outPort!));
      showLive(sample);
      if (sample == null) {
        return const FieldValue('');
      }
    case FieldKind.arg:
      // An argument's constant, until a binding replaces it (ADR 0040 §2).
      if (bound) {
        sample = live(portKey(PortSide.input, b.id, f.inPort!));
        showLive(sample);
        if (sample == null) {
          return FieldValue('', bound: bound);
        }
      } else if (b.cfgArgs[f.name] case final a?) {
        showTyped(a);
      }
  }
  final point = f.kind == FieldKind.input || f.kind == FieldKind.output;
  return FieldValue(
    switch (shown) {
      _ when jsonShortText(json) != null => jsonShortText(json)!,
      // A date of the engine (µs) reads as a date and time.
      _ when isTimeField(b.type, f.port) && dateText(shown) != null => dateText(
        shown,
      )!,
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
    json: json,
    quality: sample?.quality,
  );
}
