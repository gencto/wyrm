// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'access_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccessState {

 IList<UserInfo> get users; IList<RoleGrant> get grants; IList<String> get audit; String? get selected; String get tab;
/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccessStateCopyWith<AccessState> get copyWith => _$AccessStateCopyWithImpl<AccessState>(this as AccessState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccessState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccessState&&const DeepCollectionEquality().equals(other.users, _this.users)&&const DeepCollectionEquality().equals(other.grants, _this.grants)&&const DeepCollectionEquality().equals(other.audit, _this.audit)&&(identical(other.selected, _this.selected) || other.selected == _this.selected)&&(identical(other.tab, _this.tab) || other.tab == _this.tab));
}


@override
int get hashCode {
  final _this = this as AccessState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.users),const DeepCollectionEquality().hash(_this.grants),const DeepCollectionEquality().hash(_this.audit),_this.selected,_this.tab);
}

@override
String toString() {
  final _this = this as AccessState;
  return 'AccessState(users: ${_this.users}, grants: ${_this.grants}, audit: ${_this.audit}, selected: ${_this.selected}, tab: ${_this.tab})';
}


}

/// @nodoc
abstract mixin class $AccessStateCopyWith<$Res>  {
  factory $AccessStateCopyWith(AccessState value, $Res Function(AccessState) _then) = _$AccessStateCopyWithImpl;
@useResult
$Res call({
 IList<UserInfo> users, IList<RoleGrant> grants, IList<String> audit, String? selected, String tab
});




}
/// @nodoc
class _$AccessStateCopyWithImpl<$Res>
    implements $AccessStateCopyWith<$Res> {
  _$AccessStateCopyWithImpl(this._self, this._then);

  final AccessState _self;
  final $Res Function(AccessState) _then;

/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? users = null,Object? grants = null,Object? audit = null,Object? selected = freezed,Object? tab = null,}) {
  return _then(AccessState(
users: null == users ? _self.users : users // ignore: cast_nullable_to_non_nullable
as IList<UserInfo>,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<RoleGrant>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<String>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _AccessState implements AccessState {
  const _AccessState({this.users = const IListConst([]), this.grants = const IListConst([]), this.audit = const IListConst([]), this.selected, this.tab = 'users'});
  

@override@JsonKey() final  IList<UserInfo> users;
@override@JsonKey() final  IList<RoleGrant> grants;
@override@JsonKey() final  IList<String> audit;
@override final  String? selected;
@override@JsonKey() final  String tab;

/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccessStateCopyWith<_AccessState> get copyWith => __$AccessStateCopyWithImpl<_AccessState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccessState&&const DeepCollectionEquality().equals(other.users, users)&&const DeepCollectionEquality().equals(other.grants, grants)&&const DeepCollectionEquality().equals(other.audit, audit)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.tab, tab) || other.tab == tab));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(users),const DeepCollectionEquality().hash(grants),const DeepCollectionEquality().hash(audit),selected,tab);
}

@override
String toString() {
    return 'AccessState(users: $users, grants: $grants, audit: $audit, selected: $selected, tab: $tab)';
}


}

/// @nodoc
abstract mixin class _$AccessStateCopyWith<$Res> implements $AccessStateCopyWith<$Res> {
  factory _$AccessStateCopyWith(_AccessState value, $Res Function(_AccessState) _then) = __$AccessStateCopyWithImpl;
@override @useResult
$Res call({
 IList<UserInfo> users, IList<RoleGrant> grants, IList<String> audit, String? selected, String tab
});




}
/// @nodoc
class __$AccessStateCopyWithImpl<$Res>
    implements _$AccessStateCopyWith<$Res> {
  __$AccessStateCopyWithImpl(this._self, this._then);

  final _AccessState _self;
  final $Res Function(_AccessState) _then;

/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? users = null,Object? grants = null,Object? audit = null,Object? selected = freezed,Object? tab = null,}) {
  return _then(_AccessState(
users: null == users ? _self.users : users // ignore: cast_nullable_to_non_nullable
as IList<UserInfo>,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<RoleGrant>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<String>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
