import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'block_def.dart';
import 'flow_block.dart';
import 'flow_edge.dart';
import 'flow_permissions.dart';

part 'flow_draft.freezed.dart';

/// A flow being edited: the definition of spec 06 as blocks and edges,
/// plus the fields the editor keeps as they came (`policy`,
/// `permissions`, `description`, …).
@freezed
abstract class FlowDraft with _$FlowDraft {
  const factory FlowDraft({
    required String id,
    @Default(0) int version,
    @Default(IMapConst({})) IMap<String, FlowBlock> blocks,
    @Default(IListConst([])) IList<FlowEdge> edges,
    @Default(IMapConst({})) IMap<String, Object?> rest,

    /// The custom blocks of the definition (`blocks`), decoded, by name.
    @Default(IMapConst({})) IMap<String, BlockDef> defs,

    /// `description`, decoded (it is in [rest] too, as it came, for the
    /// write back); null when the definition has no text there.
    String? description,

    /// `permissions`, decoded (it is in [rest] too, as it came, for the
    /// write back); null when the definition has none.
    FlowPermissions? permissions,
  }) = _FlowDraft;
}
