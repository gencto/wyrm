import 'package:freezed_annotation/freezed_annotation.dart';

import 'quality.dart';

part 'live_value.freezed.dart';

@freezed
abstract class LiveValue with _$LiveValue {
  /// The last sample of a subscribed key.
  const factory LiveValue({
    required DateTime time,
    Object? value,
    @Default(Quality.good) Quality quality,
  }) = _LiveValue;
}
