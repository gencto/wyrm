import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_info.freezed.dart';

/// A user of the gateway.
@freezed
abstract class UserInfo with _$UserInfo {
  const factory UserInfo({
    required String name,
    @Default(IListConst([])) IList<String> roles,
    @Default(false) bool disabled,

    /// Devices that can log in (ADR 0050), as `/api/users` counts them.
    @Default(0) int devices,
  }) = _UserInfo;
}
