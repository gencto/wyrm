import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/engine_port.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/node_type.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'block_cfg.dart';

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
    final names = b.portNamesOf(param) ?? const <String>[];
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
final String operandValuesKey = BlockCfgKey.operandValues.wire;

/// The input port of [t] that is its main value (`in`); null when it has
/// none.
String? mainInputOf(NodeType t) => t.knownInputs.entries
    .where((e) => e.value == EnginePort.in_)
    .firstOrNull
    ?.key;

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
  // An instance of a custom block: each declared input holds a constant
  // (`values.<input>`, spec 06 0.2.24).
  if (t.type is CustomType) {
    return t.inputs.toList();
  }
  final paramPorts = {
    for (final p in t.params)
      ?(p.port ??
          (t.inputs.contains(PortEnd.inputOf(p.name))
              ? PortEnd.inputOf(p.name)
              : null)),
  };
  final main = mainInputOf(t);
  return [
    if (main != null && !paramPorts.contains(main)) main,
    for (final p in portsOf(t, b).inputs)
      if (!t.inputs.contains(p) && !paramPorts.contains(p)) p,
  ];
}

/// The constants of [b]'s operands, by port (`{in.0: "AHU-"}`).
IMap<String, JsonValue> operandValuesOf(FlowBlock b) => b.cfgValues;

/// The constant typed into operand [port] of [b] ([JsonNull]: none).
JsonValue operandValueOf(FlowBlock b, String port) =>
    operandValuesOf(b)[port] ?? const JsonNull();

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
  final m = rawFields(operandValuesOf(b));
  if (JsonValue.of(value) case JsonNull() || JsonText(text: '')) {
    m.remove(port);
  } else {
    m[port] = value;
  }
  // `values` is read as JSON while the editor builds: a map past the bound
  // is refused here, in the action, never stored (typed text cannot make
  // one, `typedJsonOf`).
  if (!JsonValue.isJson(m)) {
    throw const JsonTooDeep();
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
  final m = rawFields(operandValuesIn(cfg));
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
      if (const {
        KnownBlock.subscribe,
        KnownBlock.liveliness,
        KnownBlock.loadValue,
      }.contains(b.type.known))
        ?b.cfgKey,
    for (final b in d.blocks.values)
      if (b.type.known == KnownBlock.listChildren) ?b.cfgPath,
    // What a key from a port may read (ADR 0040 §1).
    for (final b in d.blocks.values)
      if (b.cfgScope case final k? when k.isNotEmpty) k,
  ],
  writes: [
    for (final b in d.blocks.values)
      if (const {
        KnownBlock.set,
        KnownBlock.invoke,
        KnownBlock.publish,
      }.contains(b.type.known))
        ?(b.cfgPath ?? b.cfgKey ?? b.cfgTarget),
  ],
);

/// A map or list parameter as the JSON text its field shows.
String flowJson(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

/// The JSON text of a map or list field back as a value.
Object? flowJsonDecode(String s) => jsonDecode(s);
