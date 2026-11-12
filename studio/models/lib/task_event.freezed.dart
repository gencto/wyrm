// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskEvent {

/// `ask`, `text`, `tool`, `state`, `error`.
 String get kind; String get text; DateTime? get time;
/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskEventCopyWith<TaskEvent> get copyWith => _$TaskEventCopyWithImpl<TaskEvent>(this as TaskEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskEvent&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.time, _this.time) || other.time == _this.time));
}


@override
int get hashCode {
  final _this = this as TaskEvent;
  return Object.hash(runtimeType,_this.kind,_this.text,_this.time);
}

@override
String toString() {
  final _this = this as TaskEvent;
  return 'TaskEvent(kind: ${_this.kind}, text: ${_this.text}, time: ${_this.time})';
}


}

/// @nodoc
abstract mixin class $TaskEventCopyWith<$Res>  {
  factory $TaskEventCopyWith(TaskEvent value, $Res Function(TaskEvent) _then) = _$TaskEventCopyWithImpl;
@useResult
$Res call({
 String kind, String text, DateTime? time
});




}
/// @nodoc
class _$TaskEventCopyWithImpl<$Res>
    implements $TaskEventCopyWith<$Res> {
  _$TaskEventCopyWithImpl(this._self, this._then);

  final TaskEvent _self;
  final $Res Function(TaskEvent) _then;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? text = null,Object? time = freezed,}) {
  return _then(TaskEvent(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,time: freezed == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}



/// @nodoc


class _TaskEvent implements TaskEvent {
  const _TaskEvent({required this.kind, this.text = '', this.time});
  

/// `ask`, `text`, `tool`, `state`, `error`.
@override final  String kind;
@override@JsonKey() final  String text;
@override final  DateTime? time;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskEventCopyWith<_TaskEvent> get copyWith => __$TaskEventCopyWithImpl<_TaskEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskEvent&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.text, text) || other.text == text)&&(identical(other.time, time) || other.time == time));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,text,time);
}

@override
String toString() {
    return 'TaskEvent(kind: $kind, text: $text, time: $time)';
}


}

/// @nodoc
abstract mixin class _$TaskEventCopyWith<$Res> implements $TaskEventCopyWith<$Res> {
  factory _$TaskEventCopyWith(_TaskEvent value, $Res Function(_TaskEvent) _then) = __$TaskEventCopyWithImpl;
@override @useResult
$Res call({
 String kind, String text, DateTime? time
});




}
/// @nodoc
class __$TaskEventCopyWithImpl<$Res>
    implements _$TaskEventCopyWith<$Res> {
  __$TaskEventCopyWithImpl(this._self, this._then);

  final _TaskEvent _self;
  final $Res Function(_TaskEvent) _then;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? text = null,Object? time = freezed,}) {
  return _then(_TaskEvent(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,time: freezed == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
