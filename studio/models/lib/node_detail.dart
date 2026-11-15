import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm, TypeCode;

import 'action_info.dart';

part 'node_detail.freezed.dart';

/// The full `~meta` of a node, as the inspector and the property sheet show
/// it (docs/studio.md §7.4).
@freezed
abstract class NodeDetail with _$NodeDetail {
  const factory NodeDetail({
    required String key,
    String? display,
    String? profile,
    TypeCode? type,
    String? unit,
    /// The level a set needs; null when the value cannot be set.
    Perm? writable,
    String? invokable,
    @Default(IListConst([])) IList<String> choices,
    @Default(IListConst([])) IList<ActionInfo> actions,

    /// `cfg` and `attr`, each value as text.
    @Default(IMapConst({})) IMap<String, String> cfg,
    @Default(IMapConst({})) IMap<String, String> attr,
    @Default(false) bool hasOverride,
    @Default(false) bool hasHistory,
    int? rev,
  }) = _NodeDetail;
}
