// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_finding.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskFinding {

/// The full node key (one the agent link checked the asker may read).
 String get key; String get label; String get detail;
/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskFindingCopyWith<TaskFinding> get copyWith => _$TaskFindingCopyWithImpl<TaskFinding>(this as TaskFinding, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskFinding;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskFinding&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as TaskFinding;
  return Object.hash(runtimeType,_this.key,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as TaskFinding;
  return 'TaskFinding(key: ${_this.key}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $TaskFindingCopyWith<$Res>  {
  factory $TaskFindingCopyWith(TaskFinding value, $Res Function(TaskFinding) _then) = _$TaskFindingCopyWithImpl;
@useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class _$TaskFindingCopyWithImpl<$Res>
    implements $TaskFindingCopyWith<$Res> {
  _$TaskFindingCopyWithImpl(this._self, this._then);

  final TaskFinding _self;
  final $Res Function(TaskFinding) _then;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(TaskFinding(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _TaskFinding implements TaskFinding {
  const _TaskFinding({required this.key, required this.label, this.detail = ''});
  

/// The full node key (one the agent link checked the asker may read).
@override final  String key;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskFindingCopyWith<_TaskFinding> get copyWith => __$TaskFindingCopyWithImpl<_TaskFinding>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskFinding&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,label,detail);
}

@override
String toString() {
    return 'TaskFinding(key: $key, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$TaskFindingCopyWith<$Res> implements $TaskFindingCopyWith<$Res> {
  factory _$TaskFindingCopyWith(_TaskFinding value, $Res Function(_TaskFinding) _then) = __$TaskFindingCopyWithImpl;
@override @useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class __$TaskFindingCopyWithImpl<$Res>
    implements _$TaskFindingCopyWith<$Res> {
  __$TaskFindingCopyWithImpl(this._self, this._then);

  final _TaskFinding _self;
  final $Res Function(_TaskFinding) _then;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(_TaskFinding(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
