import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'flow_block.freezed.dart';

/// One node of a flow definition (spec 06 `nodes.<id>`) and where the
/// editor draws it (`layout.<id>`).
@freezed
abstract class FlowBlock with _$FlowBlock {
  const factory FlowBlock({
    required String id,
    required String type,

    /// The node's config without `type`, as JSON values.
    @Default(IMapConst({})) IMap<String, Object?> cfg,
    @Default(0) double x,
    @Default(0) double y,

    /// The fields the user pinned to the block or took off it, by field id
    /// (`p:input_min` → true: a row of the block; false: only in the
    /// inspector). A field without an entry follows its type's default.
    /// Editor data, kept in the definition's `layout`.
    @Default(IMapConst({})) IMap<String, bool> pins,
  }) = _FlowBlock;
}
