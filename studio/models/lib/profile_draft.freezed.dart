// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProfileDraft {

/// `extends`: the profile it inherits.
 String? get parent; TypeCode? get type; String? get unit;/// `enum`: the names of its values.
 IList<String>? get enumValues; String? get display; IList<String>? get children; IMap<String, JsonValue>? get cfg; IMap<String, JsonValue>? get attr;
/// Create a copy of ProfileDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileDraftCopyWith<ProfileDraft> get copyWith => _$ProfileDraftCopyWithImpl<ProfileDraft>(this as ProfileDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileDraft&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.unit, _this.unit) || other.unit == _this.unit)&&const DeepCollectionEquality().equals(other.enumValues, _this.enumValues)&&(identical(other.display, _this.display) || other.display == _this.display)&&const DeepCollectionEquality().equals(other.children, _this.children)&&(identical(other.cfg, _this.cfg) || other.cfg == _this.cfg)&&(identical(other.attr, _this.attr) || other.attr == _this.attr));
}


@override
int get hashCode {
  final _this = this as ProfileDraft;
  return Object.hash(runtimeType,_this.parent,_this.type,_this.unit,const DeepCollectionEquality().hash(_this.enumValues),_this.display,const DeepCollectionEquality().hash(_this.children),_this.cfg,_this.attr);
}

@override
String toString() {
  final _this = this as ProfileDraft;
  return 'ProfileDraft(parent: ${_this.parent}, type: ${_this.type}, unit: ${_this.unit}, enumValues: ${_this.enumValues}, display: ${_this.display}, children: ${_this.children}, cfg: ${_this.cfg}, attr: ${_this.attr})';
}


}

/// @nodoc
abstract mixin class $ProfileDraftCopyWith<$Res>  {
  factory $ProfileDraftCopyWith(ProfileDraft value, $Res Function(ProfileDraft) _then) = _$ProfileDraftCopyWithImpl;
@useResult
$Res call({
 String? parent, TypeCode? type, String? unit, IList<String>? enumValues, String? display, IList<String>? children, IMap<String, JsonValue>? cfg, IMap<String, JsonValue>? attr
});




}
/// @nodoc
class _$ProfileDraftCopyWithImpl<$Res>
    implements $ProfileDraftCopyWith<$Res> {
  _$ProfileDraftCopyWithImpl(this._self, this._then);

  final ProfileDraft _self;
  final $Res Function(ProfileDraft) _then;

/// Create a copy of ProfileDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parent = freezed,Object? type = freezed,Object? unit = freezed,Object? enumValues = freezed,Object? display = freezed,Object? children = freezed,Object? cfg = freezed,Object? attr = freezed,}) {
  return _then(ProfileDraft(
parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TypeCode?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,enumValues: freezed == enumValues ? _self.enumValues : enumValues // ignore: cast_nullable_to_non_nullable
as IList<String>?,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,children: freezed == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as IList<String>?,cfg: freezed == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, JsonValue>?,attr: freezed == attr ? _self.attr : attr // ignore: cast_nullable_to_non_nullable
as IMap<String, JsonValue>?,
  ));
}

}



/// @nodoc


class _ProfileDraft implements ProfileDraft {
  const _ProfileDraft({this.parent, this.type, this.unit, this.enumValues, this.display, this.children, this.cfg, this.attr});
  

/// `extends`: the profile it inherits.
@override final  String? parent;
@override final  TypeCode? type;
@override final  String? unit;
/// `enum`: the names of its values.
@override final  IList<String>? enumValues;
@override final  String? display;
@override final  IList<String>? children;
@override final  IMap<String, JsonValue>? cfg;
@override final  IMap<String, JsonValue>? attr;

/// Create a copy of ProfileDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileDraftCopyWith<_ProfileDraft> get copyWith => __$ProfileDraftCopyWithImpl<_ProfileDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileDraft&&(identical(other.parent, parent) || other.parent == parent)&&(identical(other.type, type) || other.type == type)&&(identical(other.unit, unit) || other.unit == unit)&&const DeepCollectionEquality().equals(other.enumValues, enumValues)&&(identical(other.display, display) || other.display == display)&&const DeepCollectionEquality().equals(other.children, children)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.attr, attr) || other.attr == attr));
}


@override
int get hashCode {
    return Object.hash(runtimeType,parent,type,unit,const DeepCollectionEquality().hash(enumValues),display,const DeepCollectionEquality().hash(children),cfg,attr);
}

@override
String toString() {
    return 'ProfileDraft(parent: $parent, type: $type, unit: $unit, enumValues: $enumValues, display: $display, children: $children, cfg: $cfg, attr: $attr)';
}


}

/// @nodoc
abstract mixin class _$ProfileDraftCopyWith<$Res> implements $ProfileDraftCopyWith<$Res> {
  factory _$ProfileDraftCopyWith(_ProfileDraft value, $Res Function(_ProfileDraft) _then) = __$ProfileDraftCopyWithImpl;
@override @useResult
$Res call({
 String? parent, TypeCode? type, String? unit, IList<String>? enumValues, String? display, IList<String>? children, IMap<String, JsonValue>? cfg, IMap<String, JsonValue>? attr
});




}
/// @nodoc
class __$ProfileDraftCopyWithImpl<$Res>
    implements _$ProfileDraftCopyWith<$Res> {
  __$ProfileDraftCopyWithImpl(this._self, this._then);

  final _ProfileDraft _self;
  final $Res Function(_ProfileDraft) _then;

/// Create a copy of ProfileDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parent = freezed,Object? type = freezed,Object? unit = freezed,Object? enumValues = freezed,Object? display = freezed,Object? children = freezed,Object? cfg = freezed,Object? attr = freezed,}) {
  return _then(_ProfileDraft(
parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TypeCode?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,enumValues: freezed == enumValues ? _self.enumValues : enumValues // ignore: cast_nullable_to_non_nullable
as IList<String>?,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,children: freezed == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as IList<String>?,cfg: freezed == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, JsonValue>?,attr: freezed == attr ? _self.attr : attr // ignore: cast_nullable_to_non_nullable
as IMap<String, JsonValue>?,
  ));
}


}

// dart format on
