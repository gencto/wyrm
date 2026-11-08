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
  }) = _FlowBlock;
}
