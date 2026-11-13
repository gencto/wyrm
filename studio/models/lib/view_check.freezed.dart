// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'view_check.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ViewCheck {

/// `ok`, `warn` (drawn, with a placeholder or without an effect) or
/// `bad` (the document is refused or a part cannot work).
 String get level;/// The sentence shown.
 String get text;/// The component the line is about, if one.
 String? get part;/// The key the line is about, if one.
 String? get key;
/// Create a copy of ViewCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ViewCheckCopyWith<ViewCheck> get copyWith => _$ViewCheckCopyWithImpl<ViewCheck>(this as ViewCheck, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ViewCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ViewCheck&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.part, _this.part) || other.part == _this.part)&&(identical(other.key, _this.key) || other.key == _this.key));
}


@override
int get hashCode {
  final _this = this as ViewCheck;
  return Object.hash(runtimeType,_this.level,_this.text,_this.part,_this.key);
}

@override
String toString() {
  final _this = this as ViewCheck;
  return 'ViewCheck(level: ${_this.level}, text: ${_this.text}, part: ${_this.part}, key: ${_this.key})';
}


}

/// @nodoc
abstract mixin class $ViewCheckCopyWith<$Res>  {
  factory $ViewCheckCopyWith(ViewCheck value, $Res Function(ViewCheck) _then) = _$ViewCheckCopyWithImpl;
@useResult
$Res call({
 String level, String text, String? part, String? key
});




}
/// @nodoc
class _$ViewCheckCopyWithImpl<$Res>
    implements $ViewCheckCopyWith<$Res> {
  _$ViewCheckCopyWithImpl(this._self, this._then);

  final ViewCheck _self;
  final $Res Function(ViewCheck) _then;

/// Create a copy of ViewCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? level = null,Object? text = null,Object? part = freezed,Object? key = freezed,}) {
  return _then(ViewCheck(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,part: freezed == part ? _self.part : part // ignore: cast_nullable_to_non_nullable
as String?,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _ViewCheck implements ViewCheck {
  const _ViewCheck({required this.level, required this.text, this.part, this.key});
  

/// `ok`, `warn` (drawn, with a placeholder or without an effect) or
/// `bad` (the document is refused or a part cannot work).
@override final  String level;
/// The sentence shown.
@override final  String text;
/// The component the line is about, if one.
@override final  String? part;
/// The key the line is about, if one.
@override final  String? key;

/// Create a copy of ViewCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ViewCheckCopyWith<_ViewCheck> get copyWith => __$ViewCheckCopyWithImpl<_ViewCheck>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ViewCheck&&(identical(other.level, level) || other.level == level)&&(identical(other.text, text) || other.text == text)&&(identical(other.part, part) || other.part == part)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,text,part,key);
}

@override
String toString() {
    return 'ViewCheck(level: $level, text: $text, part: $part, key: $key)';
}


}

/// @nodoc
abstract mixin class _$ViewCheckCopyWith<$Res> implements $ViewCheckCopyWith<$Res> {
  factory _$ViewCheckCopyWith(_ViewCheck value, $Res Function(_ViewCheck) _then) = __$ViewCheckCopyWithImpl;
@override @useResult
$Res call({
 String level, String text, String? part, String? key
});




}
/// @nodoc
class __$ViewCheckCopyWithImpl<$Res>
    implements _$ViewCheckCopyWith<$Res> {
  __$ViewCheckCopyWithImpl(this._self, this._then);

  final _ViewCheck _self;
  final $Res Function(_ViewCheck) _then;

/// Create a copy of ViewCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? level = null,Object? text = null,Object? part = freezed,Object? key = freezed,}) {
  return _then(_ViewCheck(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,part: freezed == part ? _self.part : part // ignore: cast_nullable_to_non_nullable
as String?,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
