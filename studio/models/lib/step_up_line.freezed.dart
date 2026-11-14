// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step_up_line.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepUpLine {

/// `config` or `write`.
 String get level; String get text; String get key;
/// Create a copy of StepUpLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpLineCopyWith<StepUpLine> get copyWith => _$StepUpLineCopyWithImpl<StepUpLine>(this as StepUpLine, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StepUpLine;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpLine&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.key, _this.key) || other.key == _this.key));
}


@override
int get hashCode {
  final _this = this as StepUpLine;
  return Object.hash(runtimeType,_this.level,_this.text,_this.key);
}

@override
String toString() {
  final _this = this as StepUpLine;
  return 'StepUpLine(level: ${_this.level}, text: ${_this.text}, key: ${_this.key})';
}


}

/// @nodoc
abstract mixin class $StepUpLineCopyWith<$Res>  {
  factory $StepUpLineCopyWith(StepUpLine value, $Res Function(StepUpLine) _then) = _$StepUpLineCopyWithImpl;
@useResult
$Res call({
 String level, String text, String key
});




}
/// @nodoc
class _$StepUpLineCopyWithImpl<$Res>
    implements $StepUpLineCopyWith<$Res> {
  _$StepUpLineCopyWithImpl(this._self, this._then);

  final StepUpLine _self;
  final $Res Function(StepUpLine) _then;

/// Create a copy of StepUpLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? level = null,Object? text = null,Object? key = null,}) {
  return _then(StepUpLine(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _StepUpLine implements StepUpLine {
  const _StepUpLine({required this.level, required this.text, this.key = ''});
  

/// `config` or `write`.
@override final  String level;
@override final  String text;
@override@JsonKey() final  String key;

/// Create a copy of StepUpLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepUpLineCopyWith<_StepUpLine> get copyWith => __$StepUpLineCopyWithImpl<_StepUpLine>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StepUpLine&&(identical(other.level, level) || other.level == level)&&(identical(other.text, text) || other.text == text)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,text,key);
}

@override
String toString() {
    return 'StepUpLine(level: $level, text: $text, key: $key)';
}


}

/// @nodoc
abstract mixin class _$StepUpLineCopyWith<$Res> implements $StepUpLineCopyWith<$Res> {
  factory _$StepUpLineCopyWith(_StepUpLine value, $Res Function(_StepUpLine) _then) = __$StepUpLineCopyWithImpl;
@override @useResult
$Res call({
 String level, String text, String key
});




}
/// @nodoc
class __$StepUpLineCopyWithImpl<$Res>
    implements _$StepUpLineCopyWith<$Res> {
  __$StepUpLineCopyWithImpl(this._self, this._then);

  final _StepUpLine _self;
  final $Res Function(_StepUpLine) _then;

/// Create a copy of StepUpLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? level = null,Object? text = null,Object? key = null,}) {
  return _then(_StepUpLine(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
