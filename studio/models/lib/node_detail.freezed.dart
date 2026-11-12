// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'node_detail.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NodeDetail {

 String get key; String? get display; String? get profile; String? get type; String? get unit; String? get writable; String? get invokable; IList<String> get choices; IList<ActionInfo> get actions;/// `cfg` and `attr`, each value as text.
 IMap<String, String> get cfg; IMap<String, String> get attr; bool get hasOverride; bool get hasHistory; int? get rev;
/// Create a copy of NodeDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodeDetailCopyWith<NodeDetail> get copyWith => _$NodeDetailCopyWithImpl<NodeDetail>(this as NodeDetail, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NodeDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodeDetail&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.display, _this.display) || other.display == _this.display)&&(identical(other.profile, _this.profile) || other.profile == _this.profile)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.unit, _this.unit) || other.unit == _this.unit)&&(identical(other.writable, _this.writable) || other.writable == _this.writable)&&(identical(other.invokable, _this.invokable) || other.invokable == _this.invokable)&&const DeepCollectionEquality().equals(other.choices, _this.choices)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&(identical(other.cfg, _this.cfg) || other.cfg == _this.cfg)&&(identical(other.attr, _this.attr) || other.attr == _this.attr)&&(identical(other.hasOverride, _this.hasOverride) || other.hasOverride == _this.hasOverride)&&(identical(other.hasHistory, _this.hasHistory) || other.hasHistory == _this.hasHistory)&&(identical(other.rev, _this.rev) || other.rev == _this.rev));
}


@override
int get hashCode {
  final _this = this as NodeDetail;
  return Object.hash(runtimeType,_this.key,_this.display,_this.profile,_this.type,_this.unit,_this.writable,_this.invokable,const DeepCollectionEquality().hash(_this.choices),const DeepCollectionEquality().hash(_this.actions),_this.cfg,_this.attr,_this.hasOverride,_this.hasHistory,_this.rev);
}

@override
String toString() {
  final _this = this as NodeDetail;
  return 'NodeDetail(key: ${_this.key}, display: ${_this.display}, profile: ${_this.profile}, type: ${_this.type}, unit: ${_this.unit}, writable: ${_this.writable}, invokable: ${_this.invokable}, choices: ${_this.choices}, actions: ${_this.actions}, cfg: ${_this.cfg}, attr: ${_this.attr}, hasOverride: ${_this.hasOverride}, hasHistory: ${_this.hasHistory}, rev: ${_this.rev})';
}


}

/// @nodoc
abstract mixin class $NodeDetailCopyWith<$Res>  {
  factory $NodeDetailCopyWith(NodeDetail value, $Res Function(NodeDetail) _then) = _$NodeDetailCopyWithImpl;
@useResult
$Res call({
 String key, String? display, String? profile, String? type, String? unit, String? writable, String? invokable, IList<String> choices, IList<ActionInfo> actions, IMap<String, String> cfg, IMap<String, String> attr, bool hasOverride, bool hasHistory, int? rev
});




}
/// @nodoc
class _$NodeDetailCopyWithImpl<$Res>
    implements $NodeDetailCopyWith<$Res> {
  _$NodeDetailCopyWithImpl(this._self, this._then);

  final NodeDetail _self;
  final $Res Function(NodeDetail) _then;

/// Create a copy of NodeDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? display = freezed,Object? profile = freezed,Object? type = freezed,Object? unit = freezed,Object? writable = freezed,Object? invokable = freezed,Object? choices = null,Object? actions = null,Object? cfg = null,Object? attr = null,Object? hasOverride = null,Object? hasHistory = null,Object? rev = freezed,}) {
  return _then(NodeDetail(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,profile: freezed == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,writable: freezed == writable ? _self.writable : writable // ignore: cast_nullable_to_non_nullable
as String?,invokable: freezed == invokable ? _self.invokable : invokable // ignore: cast_nullable_to_non_nullable
as String?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as IList<ActionInfo>,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,attr: null == attr ? _self.attr : attr // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,hasOverride: null == hasOverride ? _self.hasOverride : hasOverride // ignore: cast_nullable_to_non_nullable
as bool,hasHistory: null == hasHistory ? _self.hasHistory : hasHistory // ignore: cast_nullable_to_non_nullable
as bool,rev: freezed == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}



/// @nodoc


class _NodeDetail implements NodeDetail {
  const _NodeDetail({required this.key, this.display, this.profile, this.type, this.unit, this.writable, this.invokable, this.choices = const IListConst([]), this.actions = const IListConst([]), this.cfg = const IMapConst({}), this.attr = const IMapConst({}), this.hasOverride = false, this.hasHistory = false, this.rev});
  

@override final  String key;
@override final  String? display;
@override final  String? profile;
@override final  String? type;
@override final  String? unit;
@override final  String? writable;
@override final  String? invokable;
@override@JsonKey() final  IList<String> choices;
@override@JsonKey() final  IList<ActionInfo> actions;
/// `cfg` and `attr`, each value as text.
@override@JsonKey() final  IMap<String, String> cfg;
@override@JsonKey() final  IMap<String, String> attr;
@override@JsonKey() final  bool hasOverride;
@override@JsonKey() final  bool hasHistory;
@override final  int? rev;

/// Create a copy of NodeDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodeDetailCopyWith<_NodeDetail> get copyWith => __$NodeDetailCopyWithImpl<_NodeDetail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodeDetail&&(identical(other.key, key) || other.key == key)&&(identical(other.display, display) || other.display == display)&&(identical(other.profile, profile) || other.profile == profile)&&(identical(other.type, type) || other.type == type)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.writable, writable) || other.writable == writable)&&(identical(other.invokable, invokable) || other.invokable == invokable)&&const DeepCollectionEquality().equals(other.choices, choices)&&const DeepCollectionEquality().equals(other.actions, actions)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.attr, attr) || other.attr == attr)&&(identical(other.hasOverride, hasOverride) || other.hasOverride == hasOverride)&&(identical(other.hasHistory, hasHistory) || other.hasHistory == hasHistory)&&(identical(other.rev, rev) || other.rev == rev));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,display,profile,type,unit,writable,invokable,const DeepCollectionEquality().hash(choices),const DeepCollectionEquality().hash(actions),cfg,attr,hasOverride,hasHistory,rev);
}

@override
String toString() {
    return 'NodeDetail(key: $key, display: $display, profile: $profile, type: $type, unit: $unit, writable: $writable, invokable: $invokable, choices: $choices, actions: $actions, cfg: $cfg, attr: $attr, hasOverride: $hasOverride, hasHistory: $hasHistory, rev: $rev)';
}


}

/// @nodoc
abstract mixin class _$NodeDetailCopyWith<$Res> implements $NodeDetailCopyWith<$Res> {
  factory _$NodeDetailCopyWith(_NodeDetail value, $Res Function(_NodeDetail) _then) = __$NodeDetailCopyWithImpl;
@override @useResult
$Res call({
 String key, String? display, String? profile, String? type, String? unit, String? writable, String? invokable, IList<String> choices, IList<ActionInfo> actions, IMap<String, String> cfg, IMap<String, String> attr, bool hasOverride, bool hasHistory, int? rev
});




}
/// @nodoc
class __$NodeDetailCopyWithImpl<$Res>
    implements _$NodeDetailCopyWith<$Res> {
  __$NodeDetailCopyWithImpl(this._self, this._then);

  final _NodeDetail _self;
  final $Res Function(_NodeDetail) _then;

/// Create a copy of NodeDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? display = freezed,Object? profile = freezed,Object? type = freezed,Object? unit = freezed,Object? writable = freezed,Object? invokable = freezed,Object? choices = null,Object? actions = null,Object? cfg = null,Object? attr = null,Object? hasOverride = null,Object? hasHistory = null,Object? rev = freezed,}) {
  return _then(_NodeDetail(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,profile: freezed == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,writable: freezed == writable ? _self.writable : writable // ignore: cast_nullable_to_non_nullable
as String?,invokable: freezed == invokable ? _self.invokable : invokable // ignore: cast_nullable_to_non_nullable
as String?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as IList<ActionInfo>,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,attr: null == attr ? _self.attr : attr // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,hasOverride: null == hasOverride ? _self.hasOverride : hasOverride // ignore: cast_nullable_to_non_nullable
as bool,hasHistory: null == hasHistory ? _self.hasHistory : hasHistory // ignore: cast_nullable_to_non_nullable
as bool,rev: freezed == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
