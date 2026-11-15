// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'audit_line.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuditLine {

 String get time; String get who; String get what; String get result;
/// Create a copy of AuditLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuditLineCopyWith<AuditLine> get copyWith => _$AuditLineCopyWithImpl<AuditLine>(this as AuditLine, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AuditLine;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuditLine&&(identical(other.time, _this.time) || other.time == _this.time)&&(identical(other.who, _this.who) || other.who == _this.who)&&(identical(other.what, _this.what) || other.what == _this.what)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as AuditLine;
  return Object.hash(runtimeType,_this.time,_this.who,_this.what,_this.result);
}

@override
String toString() {
  final _this = this as AuditLine;
  return 'AuditLine(time: ${_this.time}, who: ${_this.who}, what: ${_this.what}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $AuditLineCopyWith<$Res>  {
  factory $AuditLineCopyWith(AuditLine value, $Res Function(AuditLine) _then) = _$AuditLineCopyWithImpl;
@useResult
$Res call({
 String time, String who, String what, String result
});




}
/// @nodoc
class _$AuditLineCopyWithImpl<$Res>
    implements $AuditLineCopyWith<$Res> {
  _$AuditLineCopyWithImpl(this._self, this._then);

  final AuditLine _self;
  final $Res Function(AuditLine) _then;

/// Create a copy of AuditLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? who = null,Object? what = null,Object? result = null,}) {
  return _then(AuditLine(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as String,who: null == who ? _self.who : who // ignore: cast_nullable_to_non_nullable
as String,what: null == what ? _self.what : what // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _AuditLine implements AuditLine {
  const _AuditLine({this.time = '', this.who = '', this.what = '', this.result = ''});
  

@override@JsonKey() final  String time;
@override@JsonKey() final  String who;
@override@JsonKey() final  String what;
@override@JsonKey() final  String result;

/// Create a copy of AuditLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuditLineCopyWith<_AuditLine> get copyWith => __$AuditLineCopyWithImpl<_AuditLine>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuditLine&&(identical(other.time, time) || other.time == time)&&(identical(other.who, who) || other.who == who)&&(identical(other.what, what) || other.what == what)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,time,who,what,result);
}

@override
String toString() {
    return 'AuditLine(time: $time, who: $who, what: $what, result: $result)';
}


}

/// @nodoc
abstract mixin class _$AuditLineCopyWith<$Res> implements $AuditLineCopyWith<$Res> {
  factory _$AuditLineCopyWith(_AuditLine value, $Res Function(_AuditLine) _then) = __$AuditLineCopyWithImpl;
@override @useResult
$Res call({
 String time, String who, String what, String result
});




}
/// @nodoc
class __$AuditLineCopyWithImpl<$Res>
    implements _$AuditLineCopyWith<$Res> {
  __$AuditLineCopyWithImpl(this._self, this._then);

  final _AuditLine _self;
  final $Res Function(_AuditLine) _then;

/// Create a copy of AuditLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? who = null,Object? what = null,Object? result = null,}) {
  return _then(_AuditLine(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as String,who: null == who ? _self.who : who // ignore: cast_nullable_to_non_nullable
as String,what: null == what ? _self.what : what // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
