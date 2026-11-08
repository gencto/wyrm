import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/live_value.dart';

part 'live_state.freezed.dart';

@freezed
abstract class LiveState with _$LiveState {
  const factory LiveState({
    @Default(IMapConst({})) IMap<String, LiveValue> values,
    @Default(IMapConst({})) IMap<String, int> watched,
  }) = _LiveState;
}
