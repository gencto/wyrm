import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/login_failure.dart';

part 'login_state.freezed.dart';

@freezed
abstract class LoginState with _$LoginState {
  const factory LoginState({
    String? password,
    String? gateway,
    String? user,
    @Default(0) int step,
    @Default(IListConst([])) IList<String> recent,
    @Default(IMapConst({})) IMap<String, int> probes,
    @Default(true) bool remember,
    LoginFailure? failure,
    String? reason,
    @Default(0) int preload,
    @Default(IListConst([])) IList<int> preloadLate,
  }) = _LoginState;
}
