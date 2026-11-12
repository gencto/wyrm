// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hist_window.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistWindow {

 Duration get span;/// The right edge; null follows now.
 DateTime? get end;
/// Create a copy of HistWindow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistWindowCopyWith<HistWindow> get copyWith => _$HistWindowCopyWithImpl<HistWindow>(this as HistWindow, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as HistWindow;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistWindow&&(identical(other.span, _this.span) || other.span == _this.span)&&(identical(other.end, _this.end) || other.end == _this.end));
}


@override
int get hashCode {
  final _this = this as HistWindow;
  return Object.hash(runtimeType,_this.span,_this.end);
}

@override
String toString() {
  final _this = this as HistWindow;
  return 'HistWindow(span: ${_this.span}, end: ${_this.end})';
}


}

/// @nodoc
abstract mixin class $HistWindowCopyWith<$Res>  {
  factory $HistWindowCopyWith(HistWindow value, $Res Function(HistWindow) _then) = _$HistWindowCopyWithImpl;
@useResult
$Res call({
 Duration span, DateTime? end
});




}
/// @nodoc
class _$HistWindowCopyWithImpl<$Res>
    implements $HistWindowCopyWith<$Res> {
  _$HistWindowCopyWithImpl(this._self, this._then);

  final HistWindow _self;
  final $Res Function(HistWindow) _then;

/// Create a copy of HistWindow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? span = null,Object? end = freezed,}) {
  return _then(HistWindow(
span: null == span ? _self.span : span // ignore: cast_nullable_to_non_nullable
as Duration,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}



/// @nodoc


class _HistWindow extends HistWindow {
  const _HistWindow({required this.span, this.end}): super._();
  

@override final  Duration span;
/// The right edge; null follows now.
@override final  DateTime? end;

/// Create a copy of HistWindow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistWindowCopyWith<_HistWindow> get copyWith => __$HistWindowCopyWithImpl<_HistWindow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistWindow&&(identical(other.span, span) || other.span == span)&&(identical(other.end, end) || other.end == end));
}


@override
int get hashCode {
    return Object.hash(runtimeType,span,end);
}

@override
String toString() {
    return 'HistWindow(span: $span, end: $end)';
}


}

/// @nodoc
abstract mixin class _$HistWindowCopyWith<$Res> implements $HistWindowCopyWith<$Res> {
  factory _$HistWindowCopyWith(_HistWindow value, $Res Function(_HistWindow) _then) = __$HistWindowCopyWithImpl;
@override @useResult
$Res call({
 Duration span, DateTime? end
});




}
/// @nodoc
class __$HistWindowCopyWithImpl<$Res>
    implements _$HistWindowCopyWith<$Res> {
  __$HistWindowCopyWithImpl(this._self, this._then);

  final _HistWindow _self;
  final $Res Function(_HistWindow) _then;

/// Create a copy of HistWindow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? span = null,Object? end = freezed,}) {
  return _then(_HistWindow(
span: null == span ? _self.span : span // ignore: cast_nullable_to_non_nullable
as Duration,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
