// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'log_line.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LogLine {

/// As the broker wrote it (ISO 8601, UTC).
 String get time;/// `error`, `warn`, `info`, `debug`, `trace`.
 String get level;/// The module (or the `link{id=…}` span) that logged it.
 String get target; String get message;
/// Create a copy of LogLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LogLineCopyWith<LogLine> get copyWith => _$LogLineCopyWithImpl<LogLine>(this as LogLine, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LogLine;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LogLine&&(identical(other.time, _this.time) || other.time == _this.time)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as LogLine;
  return Object.hash(runtimeType,_this.time,_this.level,_this.target,_this.message);
}

@override
String toString() {
  final _this = this as LogLine;
  return 'LogLine(time: ${_this.time}, level: ${_this.level}, target: ${_this.target}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $LogLineCopyWith<$Res>  {
  factory $LogLineCopyWith(LogLine value, $Res Function(LogLine) _then) = _$LogLineCopyWithImpl;
@useResult
$Res call({
 String time, String level, String target, String message
});




}
/// @nodoc
class _$LogLineCopyWithImpl<$Res>
    implements $LogLineCopyWith<$Res> {
  _$LogLineCopyWithImpl(this._self, this._then);

  final LogLine _self;
  final $Res Function(LogLine) _then;

/// Create a copy of LogLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? level = null,Object? target = null,Object? message = null,}) {
  return _then(LogLine(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _LogLine implements LogLine {
  const _LogLine({this.time = '', this.level = '', this.target = '', this.message = ''});
  

/// As the broker wrote it (ISO 8601, UTC).
@override@JsonKey() final  String time;
/// `error`, `warn`, `info`, `debug`, `trace`.
@override@JsonKey() final  String level;
/// The module (or the `link{id=…}` span) that logged it.
@override@JsonKey() final  String target;
@override@JsonKey() final  String message;

/// Create a copy of LogLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LogLineCopyWith<_LogLine> get copyWith => __$LogLineCopyWithImpl<_LogLine>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LogLine&&(identical(other.time, time) || other.time == time)&&(identical(other.level, level) || other.level == level)&&(identical(other.target, target) || other.target == target)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,time,level,target,message);
}

@override
String toString() {
    return 'LogLine(time: $time, level: $level, target: $target, message: $message)';
}


}

/// @nodoc
abstract mixin class _$LogLineCopyWith<$Res> implements $LogLineCopyWith<$Res> {
  factory _$LogLineCopyWith(_LogLine value, $Res Function(_LogLine) _then) = __$LogLineCopyWithImpl;
@override @useResult
$Res call({
 String time, String level, String target, String message
});




}
/// @nodoc
class __$LogLineCopyWithImpl<$Res>
    implements _$LogLineCopyWith<$Res> {
  __$LogLineCopyWithImpl(this._self, this._then);

  final _LogLine _self;
  final $Res Function(_LogLine) _then;

/// Create a copy of LogLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? level = null,Object? target = null,Object? message = null,}) {
  return _then(_LogLine(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
