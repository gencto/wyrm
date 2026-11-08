import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'node_info.freezed.dart';

@freezed
abstract class NodeInfo with _$NodeInfo {
  /// One node of the tree, as `list(parent)` reports it (`~meta?view=list`).
  const factory NodeInfo({
    /// Full key, `wy/<site>/downstream/<link>/…`.
    required String key,

    /// Last key segment.
    required String name,
    String? display,

    /// TypeCode name (`number`, `bool`, `string`, …); null for a node.
    String? type,
    String? unit,

    /// `write` or `config` when the value can be set; null when it cannot.
    String? writable,

    /// A child without a type exists: the tree draws a triangle.
    @Default(false) bool hasChildren,
    @Default(false) bool hasHistory,

    /// The node has actions (`~act/*`).
    @Default(false) bool isAction,

    /// Profile (`is`), e.g. `wy:node` or `<vendor>:<model>`.
    String? profile,

    /// Enum choices of the value, if any.
    @Default(IListConst([])) IList<String> choices,
  }) = _NodeInfo;
}
