import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'assistant_state.freezed.dart';

@freezed
abstract class AssistantState with _$AssistantState {
  const factory AssistantState({
    String? draft,
    @Default(ISetConst({})) ISet<int> ticked,
    @Default('task') String panel,
    @Default(IListConst([])) IList<String> context,
  }) = _AssistantState;
}
