// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_option.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskOption {

 String get id; String get label; String get detail;
/// Create a copy of TaskOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskOptionCopyWith<TaskOption> get copyWith => _$TaskOptionCopyWithImpl<TaskOption>(this as TaskOption, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskOption;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskOption&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as TaskOption;
  return Object.hash(runtimeType,_this.id,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as TaskOption;
  return 'TaskOption(id: ${_this.id}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $TaskOptionCopyWith<$Res>  {
  factory $TaskOptionCopyWith(TaskOption value, $Res Function(TaskOption) _then) = _$TaskOptionCopyWithImpl;
@useResult
$Res call({
 String id, String label, String detail
});




}
/// @nodoc
class _$TaskOptionCopyWithImpl<$Res>
    implements $TaskOptionCopyWith<$Res> {
  _$TaskOptionCopyWithImpl(this._self, this._then);

  final TaskOption _self;
  final $Res Function(TaskOption) _then;

/// Create a copy of TaskOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? detail = null,}) {
  return _then(TaskOption(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _TaskOption implements TaskOption {
  const _TaskOption({required this.id, required this.label, this.detail = ''});
  

@override final  String id;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of TaskOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskOptionCopyWith<_TaskOption> get copyWith => __$TaskOptionCopyWithImpl<_TaskOption>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskOption&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,label,detail);
}

@override
String toString() {
    return 'TaskOption(id: $id, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$TaskOptionCopyWith<$Res> implements $TaskOptionCopyWith<$Res> {
  factory _$TaskOptionCopyWith(_TaskOption value, $Res Function(_TaskOption) _then) = __$TaskOptionCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String detail
});




}
/// @nodoc
class __$TaskOptionCopyWithImpl<$Res>
    implements _$TaskOptionCopyWith<$Res> {
  __$TaskOptionCopyWithImpl(this._self, this._then);

  final _TaskOption _self;
  final $Res Function(_TaskOption) _then;

/// Create a copy of TaskOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? detail = null,}) {
  return _then(_TaskOption(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
