// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'action_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActionInfo {

 String get name;/// The level a call needs (the action's own, else the node's
/// `invokable`; an action with neither is not callable and is no
/// [ActionInfo]).
 Perm get level; String? get display;/// The menu group (`edit`, `secrets`, `Install Link`).
 String? get group; IList<ParamSpec> get params;/// `stream`, `void`, or a type name.
 String? get result;
/// Create a copy of ActionInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionInfoCopyWith<ActionInfo> get copyWith => _$ActionInfoCopyWithImpl<ActionInfo>(this as ActionInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActionInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.display, _this.display) || other.display == _this.display)&&(identical(other.group, _this.group) || other.group == _this.group)&&const DeepCollectionEquality().equals(other.params, _this.params)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as ActionInfo;
  return Object.hash(runtimeType,_this.name,_this.level,_this.display,_this.group,const DeepCollectionEquality().hash(_this.params),_this.result);
}

@override
String toString() {
  final _this = this as ActionInfo;
  return 'ActionInfo(name: ${_this.name}, level: ${_this.level}, display: ${_this.display}, group: ${_this.group}, params: ${_this.params}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $ActionInfoCopyWith<$Res>  {
  factory $ActionInfoCopyWith(ActionInfo value, $Res Function(ActionInfo) _then) = _$ActionInfoCopyWithImpl;
@useResult
$Res call({
 String name, Perm level, String? display, String? group, IList<ParamSpec> params, String? result
});




}
/// @nodoc
class _$ActionInfoCopyWithImpl<$Res>
    implements $ActionInfoCopyWith<$Res> {
  _$ActionInfoCopyWithImpl(this._self, this._then);

  final ActionInfo _self;
  final $Res Function(ActionInfo) _then;

/// Create a copy of ActionInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? level = null,Object? display = freezed,Object? group = freezed,Object? params = null,Object? result = freezed,}) {
  return _then(ActionInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,group: freezed == group ? _self.group : group // ignore: cast_nullable_to_non_nullable
as String?,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IList<ParamSpec>,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _ActionInfo extends ActionInfo {
  const _ActionInfo({required this.name, required this.level, this.display, this.group, this.params = const IListConst([]), this.result}): super._();
  

@override final  String name;
/// The level a call needs (the action's own, else the node's
/// `invokable`; an action with neither is not callable and is no
/// [ActionInfo]).
@override final  Perm level;
@override final  String? display;
/// The menu group (`edit`, `secrets`, `Install Link`).
@override final  String? group;
@override@JsonKey() final  IList<ParamSpec> params;
/// `stream`, `void`, or a type name.
@override final  String? result;

/// Create a copy of ActionInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionInfoCopyWith<_ActionInfo> get copyWith => __$ActionInfoCopyWithImpl<_ActionInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.display, display) || other.display == display)&&(identical(other.group, group) || other.group == group)&&const DeepCollectionEquality().equals(other.params, params)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,level,display,group,const DeepCollectionEquality().hash(params),result);
}

@override
String toString() {
    return 'ActionInfo(name: $name, level: $level, display: $display, group: $group, params: $params, result: $result)';
}


}

/// @nodoc
abstract mixin class _$ActionInfoCopyWith<$Res> implements $ActionInfoCopyWith<$Res> {
  factory _$ActionInfoCopyWith(_ActionInfo value, $Res Function(_ActionInfo) _then) = __$ActionInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, Perm level, String? display, String? group, IList<ParamSpec> params, String? result
});




}
/// @nodoc
class __$ActionInfoCopyWithImpl<$Res>
    implements _$ActionInfoCopyWith<$Res> {
  __$ActionInfoCopyWithImpl(this._self, this._then);

  final _ActionInfo _self;
  final $Res Function(_ActionInfo) _then;

/// Create a copy of ActionInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? display = freezed,Object? group = freezed,Object? params = null,Object? result = freezed,}) {
  return _then(_ActionInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,group: freezed == group ? _self.group : group // ignore: cast_nullable_to_non_nullable
as String?,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IList<ParamSpec>,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
