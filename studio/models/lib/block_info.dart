import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'block_info.freezed.dart';

/// One custom block of the site's library (`dataflows` ▸ `list_blocks`,
/// spec 06 0.2.24, ADR 0040 §3).
@freezed
abstract class BlockInfo with _$BlockInfo {
  const factory BlockInfo({
    required String name,

    /// Each `put_block` is the next version.
    @Default(0) int version,
    String? description,
    @Default(IListConst([])) IList<String> inputs,
    @Default(IListConst([])) IList<String> outputs,
  }) = _BlockInfo;
}
