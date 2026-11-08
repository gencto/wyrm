import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_state.freezed.dart';

@freezed
abstract class SystemState with _$SystemState {
  const factory SystemState({
    @Default(IListConst([])) IList<String> log,
    String? logLevel,
    String? filter,
  }) = _SystemState;
}
