import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/role_grant.dart';
import 'package:models/user_info.dart';

part 'access_state.freezed.dart';

@freezed
abstract class AccessState with _$AccessState {
  const factory AccessState({
    @Default(IListConst([])) IList<UserInfo> users,
    @Default(IListConst([])) IList<RoleGrant> grants,
    @Default(IListConst([])) IList<String> audit,
    String? selected,
    @Default('users') String tab,
    @Default(false) bool shown,
  }) = _AccessState;
}
