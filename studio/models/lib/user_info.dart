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
  }) = _UserInfo;
}
