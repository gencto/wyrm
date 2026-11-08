import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_state.freezed.dart';

@freezed
abstract class LoginState with _$LoginState {
  const factory LoginState({
    String? password,
    String? gateway,
    String? user,
  }) = _LoginState;
}
