import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_option.freezed.dart';

@freezed
abstract class TaskOption with _$TaskOption {
  /// One option of a question the assistant asks (`ask_user`, ADR 0049 §5).
  const factory TaskOption({
    required String id,
    required String label,
    @Default('') String detail,
  }) = _TaskOption;
}
