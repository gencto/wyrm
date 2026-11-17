import 'package:freezed_annotation/freezed_annotation.dart';

part 'clock_state.freezed.dart';

@freezed
abstract class ClockState with _$ClockState {
  const factory ClockState({DateTime? now}) = _ClockState;
}
