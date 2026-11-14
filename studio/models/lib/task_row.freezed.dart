// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_row.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskRow {

/// The full node key; what goes into `ask {context}` when ticked.
 String get key; String get label; String get detail;
/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskRowCopyWith<TaskRow> get copyWith => _$TaskRowCopyWithImpl<TaskRow>(this as TaskRow, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskRow;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskRow&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as TaskRow;
  return Object.hash(runtimeType,_this.key,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as TaskRow;
  return 'TaskRow(key: ${_this.key}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $TaskRowCopyWith<$Res>  {
  factory $TaskRowCopyWith(TaskRow value, $Res Function(TaskRow) _then) = _$TaskRowCopyWithImpl;
@useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class _$TaskRowCopyWithImpl<$Res>
    implements $TaskRowCopyWith<$Res> {
  _$TaskRowCopyWithImpl(this._self, this._then);

  final TaskRow _self;
  final $Res Function(TaskRow) _then;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(TaskRow(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _TaskRow implements TaskRow {
  const _TaskRow({required this.key, required this.label, this.detail = ''});
  

/// The full node key; what goes into `ask {context}` when ticked.
@override final  String key;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskRowCopyWith<_TaskRow> get copyWith => __$TaskRowCopyWithImpl<_TaskRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskRow&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,label,detail);
}

@override
String toString() {
    return 'TaskRow(key: $key, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$TaskRowCopyWith<$Res> implements $TaskRowCopyWith<$Res> {
  factory _$TaskRowCopyWith(_TaskRow value, $Res Function(_TaskRow) _then) = __$TaskRowCopyWithImpl;
@override @useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class __$TaskRowCopyWithImpl<$Res>
    implements _$TaskRowCopyWith<$Res> {
  __$TaskRowCopyWithImpl(this._self, this._then);

  final _TaskRow _self;
  final $Res Function(_TaskRow) _then;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(_TaskRow(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
