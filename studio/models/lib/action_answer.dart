import 'package:freezed_annotation/freezed_annotation.dart';

part 'action_answer.freezed.dart';

/// What a broker action of `sys` answers when it says whether it did its
/// work (`install*`, `update`, `rollback`: `{success, message}`): its
/// verdict and its own words, kept verbatim.
@freezed
abstract class ActionAnswer with _$ActionAnswer {
  const factory ActionAnswer({required bool success, String? message}) =
      _ActionAnswer;
}
