import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'block_category.dart';
import 'block_type.dart';
import 'engine_port.dart';
import 'param_spec.dart';
import 'port_type.dart';

part 'node_type.freezed.dart';

/// A block type of the flow engine (`dataflows` ▸ `node_types`, spec 06).
@freezed
abstract class NodeType with _$NodeType {
  const factory NodeType({
    required BlockType type,
    @Default('') String category,
    /// [category] as a palette section the editor knows, decoded with the
    /// catalog; null for a category the engine adds later (it is drawn by
    /// its text, after the known ones).
    BlockCategory? knownCategory,
    @Default('') String description,
    @Default(IListConst([])) IList<String> inputs,
    @Default(IListConst([])) IList<String> outputs,
    /// The ports of [inputs] the editor treats in its own way
    /// ([EnginePort]), by name, decoded with the catalog. A port with
    /// another name is not here; nor are a custom block's ports, which are
    /// its author's names.
    @Default(IMapConst({})) IMap<String, EnginePort> knownInputs,
    /// The ports of [outputs] the editor treats in its own way, as
    /// [knownInputs].
    @Default(IMapConst({})) IMap<String, EnginePort> knownOutputs,

    /// Ports a parameter adds: `(param, prefix, defaults)`.
    String? dynInParam,
    @Default('') String dynInPrefix,
    @Default(IListConst([])) IList<String> dynInDefaults,
    String? dynOutParam,
    @Default('') String dynOutPrefix,
    @Default(IListConst([])) IList<String> dynOutDefaults,
    @Default(IListConst([])) IList<ParamSpec> params,

    /// The type of each port (ADR 0038 §2), by port name.
    @Default(IMapConst({})) IMap<String, PortType> portTypes,

    /// Whether inputs repeat as outputs named like them (ADR 0038 §1); null
    /// when the catalog does not say.
    bool? echoInputs,

    /// Whether its operand inputs (`in`, the variable inputs) take a typed
    /// constant in the node's config `values` (catalog `values: true`, ADR
    /// 0038 §7).
    @Default(false) bool takesValues,

    /// The parameter behind the variable inputs is a map and its keys name
    /// the ports (catalog `dyn_inputs.keys`, ADR 0040 §2: `invoke.args` →
    /// `arg.<name>`).
    @Default(false) bool dynInKeys,

    /// `dataflows/<id>` ▸ `trigger {node}` runs a node of this type once
    /// (catalog `trigger: true`, ADR 0040 §2).
    @Default(false) bool trigger,
  }) = _NodeType;
}
