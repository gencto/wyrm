import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/staged_change.dart';

part 'changes_state.freezed.dart';

@freezed
abstract class ChangesState with _$ChangesState {
  const factory ChangesState({
    @Default(IMapConst({})) IMap<String, StagedChange> table,
    @Default(IListConst([])) IList<String> view,
    @Default(false) bool open,
    String? message,
  }) = _ChangesState;
}
