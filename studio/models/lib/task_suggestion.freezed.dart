// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_suggestion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskSuggestion {

 String get id; String get label; String get detail;/// How many changes the model expects the follow-up to plan (0:
/// nothing changes). Its guess, not a check.
 int get changes;/// The plan step (`n`) this is a fix for; null: about the task.
 int? get step; IList<TaskRow> get rows;
/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskSuggestionCopyWith<TaskSuggestion> get copyWith => _$TaskSuggestionCopyWithImpl<TaskSuggestion>(this as TaskSuggestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskSuggestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskSuggestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.changes, _this.changes) || other.changes == _this.changes)&&(identical(other.step, _this.step) || other.step == _this.step)&&const DeepCollectionEquality().equals(other.rows, _this.rows));
}


@override
int get hashCode {
  final _this = this as TaskSuggestion;
  return Object.hash(runtimeType,_this.id,_this.label,_this.detail,_this.changes,_this.step,const DeepCollectionEquality().hash(_this.rows));
}

@override
String toString() {
  final _this = this as TaskSuggestion;
  return 'TaskSuggestion(id: ${_this.id}, label: ${_this.label}, detail: ${_this.detail}, changes: ${_this.changes}, step: ${_this.step}, rows: ${_this.rows})';
}


}

/// @nodoc
abstract mixin class $TaskSuggestionCopyWith<$Res>  {
  factory $TaskSuggestionCopyWith(TaskSuggestion value, $Res Function(TaskSuggestion) _then) = _$TaskSuggestionCopyWithImpl;
@useResult
$Res call({
 String id, String label, String detail, int changes, int? step, IList<TaskRow> rows
});




}
/// @nodoc
class _$TaskSuggestionCopyWithImpl<$Res>
    implements $TaskSuggestionCopyWith<$Res> {
  _$TaskSuggestionCopyWithImpl(this._self, this._then);

  final TaskSuggestion _self;
  final $Res Function(TaskSuggestion) _then;

/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? detail = null,Object? changes = null,Object? step = freezed,Object? rows = null,}) {
  return _then(TaskSuggestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as int,step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int?,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as IList<TaskRow>,
  ));
}

}



/// @nodoc


class _TaskSuggestion implements TaskSuggestion {
  const _TaskSuggestion({required this.id, required this.label, this.detail = '', this.changes = 0, this.step, this.rows = const IListConst([])});
  

@override final  String id;
@override final  String label;
@override@JsonKey() final  String detail;
/// How many changes the model expects the follow-up to plan (0:
/// nothing changes). Its guess, not a check.
@override@JsonKey() final  int changes;
/// The plan step (`n`) this is a fix for; null: about the task.
@override final  int? step;
@override@JsonKey() final  IList<TaskRow> rows;

/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskSuggestionCopyWith<_TaskSuggestion> get copyWith => __$TaskSuggestionCopyWithImpl<_TaskSuggestion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskSuggestion&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.changes, changes) || other.changes == changes)&&(identical(other.step, step) || other.step == step)&&const DeepCollectionEquality().equals(other.rows, rows));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,label,detail,changes,step,const DeepCollectionEquality().hash(rows));
}

@override
String toString() {
    return 'TaskSuggestion(id: $id, label: $label, detail: $detail, changes: $changes, step: $step, rows: $rows)';
}


}

/// @nodoc
abstract mixin class _$TaskSuggestionCopyWith<$Res> implements $TaskSuggestionCopyWith<$Res> {
  factory _$TaskSuggestionCopyWith(_TaskSuggestion value, $Res Function(_TaskSuggestion) _then) = __$TaskSuggestionCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String detail, int changes, int? step, IList<TaskRow> rows
});




}
/// @nodoc
class __$TaskSuggestionCopyWithImpl<$Res>
    implements _$TaskSuggestionCopyWith<$Res> {
  __$TaskSuggestionCopyWithImpl(this._self, this._then);

  final _TaskSuggestion _self;
  final $Res Function(_TaskSuggestion) _then;

/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? detail = null,Object? changes = null,Object? step = freezed,Object? rows = null,}) {
  return _then(_TaskSuggestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as int,step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int?,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as IList<TaskRow>,
  ));
}


}

// dart format on
