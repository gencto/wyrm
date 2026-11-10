import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/studio_error.dart';
import 'package:models/studio_notice.dart';

part 'problems_state.freezed.dart';

@freezed
abstract class ProblemsState with _$ProblemsState {
  const factory ProblemsState({
    @Default(IListConst([])) IList<StudioError> items,
    @Default(0) int unread,
    @Default(false) bool open,
    @Default(IListConst([])) IList<int> toasts,
    @Default(IListConst([])) IList<StudioNotice> notices,
  }) = _ProblemsState;
}
