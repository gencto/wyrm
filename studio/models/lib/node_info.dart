import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm, TypeCode;

import 'node_glyph.dart';

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
    TypeCode? type,
    String? unit,

    /// The level a set needs (`write` or `config`); null when the value
    /// cannot be set.
    Perm? writable,

    /// A child without a type exists: the tree draws a triangle.
    @Default(false) bool hasChildren,
    @Default(false) bool hasHistory,

    /// The node has actions (`~act/*`).
    @Default(false) bool isAction,

    /// Profile (`is`), e.g. `wy:node` or `<vendor>:<model>`.
    String? profile,

    /// What the node is drawn as, decoded with the rest of its meta from
    /// its place and its profile (`nodeGlyphOf`). A node made without its
    /// meta (a test's, a section's) is a folder.
    @Default(NodeGlyph.section) NodeGlyph glyph,

    /// Enum choices of the value, if any.
    @Default(IListConst([])) IList<String> choices,
  }) = _NodeInfo;
}
