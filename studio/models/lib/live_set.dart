import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'live_set.freezed.dart';

/// What one shown screen keeps live: the value keys (or `*` patterns) it
/// subscribes and the keys whose children it lists. Kept by the screen's
/// slice while its tab is shown, so a hide or a site switch closes exactly
/// these and nothing else.
@freezed
abstract class LiveSet with _$LiveSet {
  const factory LiveSet({
    @Default(IListConst([])) IList<String> values,
    @Default(IListConst([])) IList<String> lists,
  }) = _LiveSet;
}
