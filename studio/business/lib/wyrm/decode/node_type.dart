import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:models/port_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'decoded.dart';

const _shape = 'node type';

/// One entry of `dataflows` ▸ `node_types` (spec 06, "Каталог типів нод")
/// as a [NodeType].
///
/// An entry that is not a map, or one with no `type` text, is [Invalid]:
/// the catalog lists it under no name, so the editor cannot draw it.
///
/// Two things are read leniently, by decision (studio-rules §8, phase B1),
/// each with a warning in [decodeLog] that names the field:
/// - `params[].type` that is no `TypeCode` name is [TypeCode.dynamic_]
///   (its value is typed as JSON, the engine's validation says what is
///   wrong). `int`, written by catalogs before ADR 0038, is
///   [TypeCode.number] without a warning. A parameter with no `type` is
///   [TypeCode.string].
/// - `port_types.<port>` that is no [PortType] name is [PortType.any]:
///   such a port takes any wire, as the engine's own unknown ports do.
///
/// An `editor` this Studio does not know is null: a UI ignores an editor
/// it does not know (spec 02).
Decoded<NodeType> nodeTypeOf(Value m) {
  if (m is! VMap) {
    return const Invalid(_shape, '', 'not a map');
  }
  final type = switch (m['type']) {
    VStr(:final v) when v.isNotEmpty => v,
    _ => null,
  };
  if (type == null) {
    return const Invalid(_shape, 'type', 'missing');
  }
  List<String> texts(Value? v) => switch (v) {
    VArray(:final v) => [for (final x in v) ?str(x)],
    _ => const [],
  };
  final dynIn = m['dyn_inputs'];
  final dynOut = m['dyn_outputs'];
  return Valid(
    NodeType(
      type: BlockType.fromWire(type),
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
          for (final (i, p) in v.indexed)
            ParamSpec(
              name: str(p['name']) ?? '',
              // The label the engine gives a field where the one derived
              // from its name would be wrong (spec 06 0.2.29: `atan.x`).
              display: str(p['display']),
              type: paramTypeOf(
                p['type'],
                where: type,
                field: 'params[$i].type',
              ),
              required: boolean(p['required']) ?? false,
              description: str(p['description']),
              choices: texts(p['choices']).lock,
              defaultValue: toDart(p['default']),
              editor: switch (str(p['editor'])) {
                final e? => ParamEditor.fromWire(e),
                null => null,
              },
              port: str(p['port']),
              echo: boolean(p['echo']),
              scope: str(p['scope']),
            ),
      ].lock,
      portTypes: {
        if (m['port_types'] case VMap(:final v))
          for (final e in v.entries)
            e.key: portTypeOf(
              e.value,
              where: type,
              field: 'port_types.${e.key}',
            ),
      }.lock,
      echoInputs: boolean(m['echo_inputs']),
      takesValues: boolean(m['values']) ?? false,
      dynInKeys: boolean(dynIn?['keys']) ?? false,
      trigger: boolean(m['trigger']) ?? false,
    ),
  );
}

/// `params[].type`: a `TypeCode` name; `int` (before ADR 0038) is a
/// number; none is a string; anything else is `dynamic`, with a warning.
TypeCode paramTypeOf(
  Value? v, {
  required String where,
  required String field,
}) => switch (v) {
  null || VNull() => TypeCode.string,
  VStr(v: 'int') => TypeCode.number,
  VStr(:final v) when TypeCode.fromWire(v) != null => TypeCode.fromWire(v)!,
  _ => _lenient(where, field, 'not a type', TypeCode.dynamic_),
};

/// `port_types.<port>`: a [PortType] name; anything else is `any`, with a
/// warning.
PortType portTypeOf(
  Value? v, {
  required String where,
  required String field,
}) => switch (v) {
  VStr(:final v) when PortType.fromWire(v) != null => PortType.fromWire(v)!,
  _ => _lenient(where, field, 'not a port type', PortType.any),
};

T _lenient<T>(String where, String field, String reason, T value) {
  decodeLog.warning('$where: $_shape.$field: $reason');
  return value;
}

/// The catalog `node_types` answers: an array of entries, each
/// [nodeTypeOf]; an entry that does not read is left out with a warning
/// naming [where]. Sorted by category, then type. Not an array: none.
List<NodeType> nodeTypesOf(Value catalog, {required String where}) {
  final entries = switch (catalog) {
    VArray(:final v) => v,
    _ => _lenient(where, '', 'not an array', const <Value>[]),
  };
  return [for (final t in entries) ?nodeTypeOf(t).orWarn(where)]..sort(
    (a, b) => a.category == b.category
        ? a.type.wire.compareTo(b.type.wire)
        : a.category.compareTo(b.category),
  );
}
