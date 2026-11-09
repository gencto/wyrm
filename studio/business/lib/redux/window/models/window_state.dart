import 'package:freezed_annotation/freezed_annotation.dart';

part 'window_state.freezed.dart';

@freezed
abstract class WindowState with _$WindowState {
  const factory WindowState({
    @Default(false) bool maximized,
    @Default(false) bool fullScreen,
    double? left,
    double? top,
    double? width,
    double? height,
  }) = _WindowState;
}
