import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'param_spec.dart';

part 'node_type.freezed.dart';

/// A block type of the flow engine (`dataflows` ▸ `node_types`, spec 06).
@freezed
abstract class NodeType with _$NodeType {
  const factory NodeType({
    required String type,
    @Default('') String category,
    @Default('') String description,
    @Default(IListConst([])) IList<String> inputs,
    @Default(IListConst([])) IList<String> outputs,

    /// Ports a parameter adds: `(param, prefix, defaults)`.
    String? dynInParam,
    @Default('') String dynInPrefix,
    @Default(IListConst([])) IList<String> dynInDefaults,
    String? dynOutParam,
    @Default('') String dynOutPrefix,
    @Default(IListConst([])) IList<String> dynOutDefaults,
    @Default(IListConst([])) IList<ParamSpec> params,

    /// The type of each port (`number`, `bool`, `any`, …; ADR 0038 §2).
    @Default(IMapConst({})) IMap<String, String> portTypes,

    /// Whether inputs repeat as outputs named like them (ADR 0038 §1); null
    /// when the catalog does not say.
    bool? echoInputs,

    /// Whether its operand inputs (`in`, the variable inputs) take a typed
    /// constant in the node's config `values` (catalog `values: true`, ADR
    /// 0038 §7).
    @Default(false) bool takesValues,
  }) = _NodeType;
}
