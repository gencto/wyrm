// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'node_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NodeInfo {

/// Full key, `wy/<site>/downstream/<link>/…`.
 String get key;/// Last key segment.
 String get name; String? get display;/// TypeCode name (`number`, `bool`, `string`, …); null for a node.
 String? get type; String? get unit;/// `write` or `config` when the value can be set; null when it cannot.
 String? get writable;/// A child without a type exists: the tree draws a triangle.
 bool get hasChildren; bool get hasHistory;/// The node has actions (`~act/*`).
 bool get isAction;/// Profile (`is`), e.g. `wy:node` or `<vendor>:<model>`.
 String? get profile;/// Enum choices of the value, if any.
 IList<String> get choices;
/// Create a copy of NodeInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodeInfoCopyWith<NodeInfo> get copyWith => _$NodeInfoCopyWithImpl<NodeInfo>(this as NodeInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodeInfo&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.display, display) || other.display == display)&&(identical(other.type, type) || other.type == type)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.writable, writable) || other.writable == writable)&&(identical(other.hasChildren, hasChildren) || other.hasChildren == hasChildren)&&(identical(other.hasHistory, hasHistory) || other.hasHistory == hasHistory)&&(identical(other.isAction, isAction) || other.isAction == isAction)&&(identical(other.profile, profile) || other.profile == profile)&&const DeepCollectionEquality().equals(other.choices, choices));
}


@override
int get hashCode => Object.hash(runtimeType,key,name,display,type,unit,writable,hasChildren,hasHistory,isAction,profile,const DeepCollectionEquality().hash(choices));

@override
String toString() {
  return 'NodeInfo(key: $key, name: $name, display: $display, type: $type, unit: $unit, writable: $writable, hasChildren: $hasChildren, hasHistory: $hasHistory, isAction: $isAction, profile: $profile, choices: $choices)';
}


}

/// @nodoc
abstract mixin class $NodeInfoCopyWith<$Res>  {
  factory $NodeInfoCopyWith(NodeInfo value, $Res Function(NodeInfo) _then) = _$NodeInfoCopyWithImpl;
@useResult
$Res call({
 String key, String name, String? display, String? type, String? unit, String? writable, bool hasChildren, bool hasHistory, bool isAction, String? profile, IList<String> choices
});




}
/// @nodoc
class _$NodeInfoCopyWithImpl<$Res>
    implements $NodeInfoCopyWith<$Res> {
  _$NodeInfoCopyWithImpl(this._self, this._then);

  final NodeInfo _self;
  final $Res Function(NodeInfo) _then;

/// Create a copy of NodeInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,Object? display = freezed,Object? type = freezed,Object? unit = freezed,Object? writable = freezed,Object? hasChildren = null,Object? hasHistory = null,Object? isAction = null,Object? profile = freezed,Object? choices = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,writable: freezed == writable ? _self.writable : writable // ignore: cast_nullable_to_non_nullable
as String?,hasChildren: null == hasChildren ? _self.hasChildren : hasChildren // ignore: cast_nullable_to_non_nullable
as bool,hasHistory: null == hasHistory ? _self.hasHistory : hasHistory // ignore: cast_nullable_to_non_nullable
as bool,isAction: null == isAction ? _self.isAction : isAction // ignore: cast_nullable_to_non_nullable
as bool,profile: freezed == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as String?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _NodeInfo implements NodeInfo {
  const _NodeInfo({required this.key, required this.name, this.display, this.type, this.unit, this.writable, this.hasChildren = false, this.hasHistory = false, this.isAction = false, this.profile, this.choices = const IListConst([])});
  

/// Full key, `wy/<site>/downstream/<link>/…`.
@override final  String key;
/// Last key segment.
@override final  String name;
@override final  String? display;
/// TypeCode name (`number`, `bool`, `string`, …); null for a node.
@override final  String? type;
@override final  String? unit;
/// `write` or `config` when the value can be set; null when it cannot.
@override final  String? writable;
/// A child without a type exists: the tree draws a triangle.
@override@JsonKey() final  bool hasChildren;
@override@JsonKey() final  bool hasHistory;
/// The node has actions (`~act/*`).
@override@JsonKey() final  bool isAction;
/// Profile (`is`), e.g. `wy:node` or `<vendor>:<model>`.
@override final  String? profile;
/// Enum choices of the value, if any.
@override@JsonKey() final  IList<String> choices;

/// Create a copy of NodeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodeInfoCopyWith<_NodeInfo> get copyWith => __$NodeInfoCopyWithImpl<_NodeInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodeInfo&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.display, display) || other.display == display)&&(identical(other.type, type) || other.type == type)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.writable, writable) || other.writable == writable)&&(identical(other.hasChildren, hasChildren) || other.hasChildren == hasChildren)&&(identical(other.hasHistory, hasHistory) || other.hasHistory == hasHistory)&&(identical(other.isAction, isAction) || other.isAction == isAction)&&(identical(other.profile, profile) || other.profile == profile)&&const DeepCollectionEquality().equals(other.choices, choices));
}


@override
int get hashCode => Object.hash(runtimeType,key,name,display,type,unit,writable,hasChildren,hasHistory,isAction,profile,const DeepCollectionEquality().hash(choices));

@override
String toString() {
  return 'NodeInfo(key: $key, name: $name, display: $display, type: $type, unit: $unit, writable: $writable, hasChildren: $hasChildren, hasHistory: $hasHistory, isAction: $isAction, profile: $profile, choices: $choices)';
}


}

/// @nodoc
abstract mixin class _$NodeInfoCopyWith<$Res> implements $NodeInfoCopyWith<$Res> {
  factory _$NodeInfoCopyWith(_NodeInfo value, $Res Function(_NodeInfo) _then) = __$NodeInfoCopyWithImpl;
@override @useResult
$Res call({
 String key, String name, String? display, String? type, String? unit, String? writable, bool hasChildren, bool hasHistory, bool isAction, String? profile, IList<String> choices
});




}
/// @nodoc
class __$NodeInfoCopyWithImpl<$Res>
    implements _$NodeInfoCopyWith<$Res> {
  __$NodeInfoCopyWithImpl(this._self, this._then);

  final _NodeInfo _self;
  final $Res Function(_NodeInfo) _then;

/// Create a copy of NodeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,Object? display = freezed,Object? type = freezed,Object? unit = freezed,Object? writable = freezed,Object? hasChildren = null,Object? hasHistory = null,Object? isAction = null,Object? profile = freezed,Object? choices = null,}) {
  return _then(_NodeInfo(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,writable: freezed == writable ? _self.writable : writable // ignore: cast_nullable_to_non_nullable
as String?,hasChildren: null == hasChildren ? _self.hasChildren : hasChildren // ignore: cast_nullable_to_non_nullable
as bool,hasHistory: null == hasHistory ? _self.hasHistory : hasHistory // ignore: cast_nullable_to_non_nullable
as bool,isAction: null == isAction ? _self.isAction : isAction // ignore: cast_nullable_to_non_nullable
as bool,profile: freezed == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as String?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
