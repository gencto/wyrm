import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'assistant_state.freezed.dart';

@freezed
abstract class AssistantState with _$AssistantState {
  const factory AssistantState({
    String? draft,
    @Default('task') String panel,
    String? agent,
    @Default(IMapConst({})) IMap<String, String> cfg,
  }) = _AssistantState;
}
