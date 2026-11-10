// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fault_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FaultReport {

/// The Dart type of what was thrown (`FormatException`).
 String get type;/// The first line of its text. Never a value, a token or a password:
/// the report leaves this computer when the user sends it.
 String get line;/// Where it was thrown: the action, or `file › member` of the first
/// stack frame inside Studio.
 String get where;/// The screen or the panel it belongs to, when known.
 String? get screen;/// The stack trace; in the copied report only, never on screen.
 String get stack;
/// Create a copy of FaultReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FaultReportCopyWith<FaultReport> get copyWith => _$FaultReportCopyWithImpl<FaultReport>(this as FaultReport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FaultReport&&(identical(other.type, type) || other.type == type)&&(identical(other.line, line) || other.line == line)&&(identical(other.where, where) || other.where == where)&&(identical(other.screen, screen) || other.screen == screen)&&(identical(other.stack, stack) || other.stack == stack));
}


@override
int get hashCode => Object.hash(runtimeType,type,line,where,screen,stack);

@override
String toString() {
  return 'FaultReport(type: $type, line: $line, where: $where, screen: $screen, stack: $stack)';
}


}

/// @nodoc
abstract mixin class $FaultReportCopyWith<$Res>  {
  factory $FaultReportCopyWith(FaultReport value, $Res Function(FaultReport) _then) = _$FaultReportCopyWithImpl;
@useResult
$Res call({
 String type, String line, String where, String? screen, String stack
});




}
/// @nodoc
class _$FaultReportCopyWithImpl<$Res>
    implements $FaultReportCopyWith<$Res> {
  _$FaultReportCopyWithImpl(this._self, this._then);

  final FaultReport _self;
  final $Res Function(FaultReport) _then;

/// Create a copy of FaultReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? line = null,Object? where = null,Object? screen = freezed,Object? stack = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,line: null == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as String,where: null == where ? _self.where : where // ignore: cast_nullable_to_non_nullable
as String,screen: freezed == screen ? _self.screen : screen // ignore: cast_nullable_to_non_nullable
as String?,stack: null == stack ? _self.stack : stack // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _FaultReport implements FaultReport {
  const _FaultReport({this.type = '', this.line = '', this.where = '', this.screen, this.stack = ''});
  

/// The Dart type of what was thrown (`FormatException`).
@override@JsonKey() final  String type;
/// The first line of its text. Never a value, a token or a password:
/// the report leaves this computer when the user sends it.
@override@JsonKey() final  String line;
/// Where it was thrown: the action, or `file › member` of the first
/// stack frame inside Studio.
@override@JsonKey() final  String where;
/// The screen or the panel it belongs to, when known.
@override final  String? screen;
/// The stack trace; in the copied report only, never on screen.
@override@JsonKey() final  String stack;

/// Create a copy of FaultReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FaultReportCopyWith<_FaultReport> get copyWith => __$FaultReportCopyWithImpl<_FaultReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FaultReport&&(identical(other.type, type) || other.type == type)&&(identical(other.line, line) || other.line == line)&&(identical(other.where, where) || other.where == where)&&(identical(other.screen, screen) || other.screen == screen)&&(identical(other.stack, stack) || other.stack == stack));
}


@override
int get hashCode => Object.hash(runtimeType,type,line,where,screen,stack);

@override
String toString() {
  return 'FaultReport(type: $type, line: $line, where: $where, screen: $screen, stack: $stack)';
}


}

/// @nodoc
abstract mixin class _$FaultReportCopyWith<$Res> implements $FaultReportCopyWith<$Res> {
  factory _$FaultReportCopyWith(_FaultReport value, $Res Function(_FaultReport) _then) = __$FaultReportCopyWithImpl;
@override @useResult
$Res call({
 String type, String line, String where, String? screen, String stack
});




}
/// @nodoc
class __$FaultReportCopyWithImpl<$Res>
    implements _$FaultReportCopyWith<$Res> {
  __$FaultReportCopyWithImpl(this._self, this._then);

  final _FaultReport _self;
  final $Res Function(_FaultReport) _then;

/// Create a copy of FaultReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? line = null,Object? where = null,Object? screen = freezed,Object? stack = null,}) {
  return _then(_FaultReport(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,line: null == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as String,where: null == where ? _self.where : where // ignore: cast_nullable_to_non_nullable
as String,screen: freezed == screen ? _self.screen : screen // ignore: cast_nullable_to_non_nullable
as String?,stack: null == stack ? _self.stack : stack // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
