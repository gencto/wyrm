// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'access_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccessState {

 IList<UserInfo> get users; IList<RoleGrant> get grants; IList<String> get audit; String? get selected; String get tab; bool get shown;
/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccessStateCopyWith<AccessState> get copyWith => _$AccessStateCopyWithImpl<AccessState>(this as AccessState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccessState&&const DeepCollectionEquality().equals(other.users, users)&&const DeepCollectionEquality().equals(other.grants, grants)&&const DeepCollectionEquality().equals(other.audit, audit)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.shown, shown) || other.shown == shown));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(users),const DeepCollectionEquality().hash(grants),const DeepCollectionEquality().hash(audit),selected,tab,shown);

@override
String toString() {
  return 'AccessState(users: $users, grants: $grants, audit: $audit, selected: $selected, tab: $tab, shown: $shown)';
}


}

/// @nodoc
abstract mixin class $AccessStateCopyWith<$Res>  {
  factory $AccessStateCopyWith(AccessState value, $Res Function(AccessState) _then) = _$AccessStateCopyWithImpl;
@useResult
$Res call({
 IList<UserInfo> users, IList<RoleGrant> grants, IList<String> audit, String? selected, String tab, bool shown
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
@pragma('vm:prefer-inline') @override $Res call({Object? users = null,Object? grants = null,Object? audit = null,Object? selected = freezed,Object? tab = null,Object? shown = null,}) {
  return _then(_self.copyWith(
users: null == users ? _self.users : users // ignore: cast_nullable_to_non_nullable
as IList<UserInfo>,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<RoleGrant>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<String>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _AccessState implements AccessState {
  const _AccessState({this.users = const IListConst([]), this.grants = const IListConst([]), this.audit = const IListConst([]), this.selected, this.tab = 'users', this.shown = false});
  

@override@JsonKey() final  IList<UserInfo> users;
@override@JsonKey() final  IList<RoleGrant> grants;
@override@JsonKey() final  IList<String> audit;
@override final  String? selected;
@override@JsonKey() final  String tab;
@override@JsonKey() final  bool shown;

/// Create a copy of AccessState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccessStateCopyWith<_AccessState> get copyWith => __$AccessStateCopyWithImpl<_AccessState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccessState&&const DeepCollectionEquality().equals(other.users, users)&&const DeepCollectionEquality().equals(other.grants, grants)&&const DeepCollectionEquality().equals(other.audit, audit)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.shown, shown) || other.shown == shown));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(users),const DeepCollectionEquality().hash(grants),const DeepCollectionEquality().hash(audit),selected,tab,shown);

@override
String toString() {
  return 'AccessState(users: $users, grants: $grants, audit: $audit, selected: $selected, tab: $tab, shown: $shown)';
}


}

/// @nodoc
abstract mixin class _$AccessStateCopyWith<$Res> implements $AccessStateCopyWith<$Res> {
  factory _$AccessStateCopyWith(_AccessState value, $Res Function(_AccessState) _then) = __$AccessStateCopyWithImpl;
@override @useResult
$Res call({
 IList<UserInfo> users, IList<RoleGrant> grants, IList<String> audit, String? selected, String tab, bool shown
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
@override @pragma('vm:prefer-inline') $Res call({Object? users = null,Object? grants = null,Object? audit = null,Object? selected = freezed,Object? tab = null,Object? shown = null,}) {
  return _then(_AccessState(
users: null == users ? _self.users : users // ignore: cast_nullable_to_non_nullable
as IList<UserInfo>,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<RoleGrant>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<String>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
