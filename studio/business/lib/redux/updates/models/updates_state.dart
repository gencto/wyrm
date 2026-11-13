import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'updates_state.freezed.dart';

@freezed
abstract class UpdatesState with _$UpdatesState {
  const factory UpdatesState({
    String? package,
    @Default('review') String view,
    @Default(true) bool takePoint,
    @Default(true) bool autoRollback,
    @Default(false) bool acceptNew,
    String? asks,
    String? message,
    @Default(0) int seenAt,
    String? seenResult,
    @Default(IListConst([])) IList<String> queue,
    String? fileName,
  }) = _UpdatesState;
}
