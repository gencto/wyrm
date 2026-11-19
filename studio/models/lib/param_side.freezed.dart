// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'param_side.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParamSide {

 String get name; String? get text; IList<String>? get list;
/// Create a copy of ParamSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParamSideCopyWith<ParamSide> get copyWith => _$ParamSideCopyWithImpl<ParamSide>(this as ParamSide, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ParamSide;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParamSide&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.list, _this.list));
}


@override
int get hashCode {
  final _this = this as ParamSide;
  return Object.hash(runtimeType,_this.name,_this.text,const DeepCollectionEquality().hash(_this.list));
}

@override
String toString() {
  final _this = this as ParamSide;
  return 'ParamSide(name: ${_this.name}, text: ${_this.text}, list: ${_this.list})';
}


}

/// @nodoc
abstract mixin class $ParamSideCopyWith<$Res>  {
  factory $ParamSideCopyWith(ParamSide value, $Res Function(ParamSide) _then) = _$ParamSideCopyWithImpl;
@useResult
$Res call({
 String name, String? text, IList<String>? list
});




}
/// @nodoc
class _$ParamSideCopyWithImpl<$Res>
    implements $ParamSideCopyWith<$Res> {
  _$ParamSideCopyWithImpl(this._self, this._then);

  final ParamSide _self;
  final $Res Function(ParamSide) _then;

/// Create a copy of ParamSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? text = freezed,Object? list = freezed,}) {
  return _then(ParamSide(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,list: freezed == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as IList<String>?,
  ));
}

}



/// @nodoc


class _ParamSide implements ParamSide {
  const _ParamSide({required this.name, this.text, this.list});
  

@override final  String name;
@override final  String? text;
@override final  IList<String>? list;

/// Create a copy of ParamSide
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParamSideCopyWith<_ParamSide> get copyWith => __$ParamSideCopyWithImpl<_ParamSide>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParamSide&&(identical(other.name, name) || other.name == name)&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other.list, list));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,text,const DeepCollectionEquality().hash(list));
}

@override
String toString() {
    return 'ParamSide(name: $name, text: $text, list: $list)';
}


}

/// @nodoc
abstract mixin class _$ParamSideCopyWith<$Res> implements $ParamSideCopyWith<$Res> {
  factory _$ParamSideCopyWith(_ParamSide value, $Res Function(_ParamSide) _then) = __$ParamSideCopyWithImpl;
@override @useResult
$Res call({
 String name, String? text, IList<String>? list
});




}
/// @nodoc
class __$ParamSideCopyWithImpl<$Res>
    implements _$ParamSideCopyWith<$Res> {
  __$ParamSideCopyWithImpl(this._self, this._then);

  final _ParamSide _self;
  final $Res Function(_ParamSide) _then;

/// Create a copy of ParamSide
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? text = freezed,Object? list = freezed,}) {
  return _then(_ParamSide(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,list: freezed == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as IList<String>?,
  ));
}


}

// dart format on
