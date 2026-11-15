// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'action_answer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActionAnswer {

/// The records' fields, in the order first seen (at most six).
 IList<String> get columns;/// One cell per column, as text; empty when the answer is no table.
 IList<IList<String>> get rows;/// How many rows the action answered.
 int get count;/// Each row as indented JSON, split into lines.
 IList<String> get lines;
/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionAnswerCopyWith<ActionAnswer> get copyWith => _$ActionAnswerCopyWithImpl<ActionAnswer>(this as ActionAnswer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActionAnswer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionAnswer&&const DeepCollectionEquality().equals(other.columns, _this.columns)&&const DeepCollectionEquality().equals(other.rows, _this.rows)&&(identical(other.count, _this.count) || other.count == _this.count)&&const DeepCollectionEquality().equals(other.lines, _this.lines));
}


@override
int get hashCode {
  final _this = this as ActionAnswer;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.columns),const DeepCollectionEquality().hash(_this.rows),_this.count,const DeepCollectionEquality().hash(_this.lines));
}

@override
String toString() {
  final _this = this as ActionAnswer;
  return 'ActionAnswer(columns: ${_this.columns}, rows: ${_this.rows}, count: ${_this.count}, lines: ${_this.lines})';
}


}

/// @nodoc
abstract mixin class $ActionAnswerCopyWith<$Res>  {
  factory $ActionAnswerCopyWith(ActionAnswer value, $Res Function(ActionAnswer) _then) = _$ActionAnswerCopyWithImpl;
@useResult
$Res call({
 IList<String> columns, IList<IList<String>> rows, int count, IList<String> lines
});




}
/// @nodoc
class _$ActionAnswerCopyWithImpl<$Res>
    implements $ActionAnswerCopyWith<$Res> {
  _$ActionAnswerCopyWithImpl(this._self, this._then);

  final ActionAnswer _self;
  final $Res Function(ActionAnswer) _then;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? columns = null,Object? rows = null,Object? count = null,Object? lines = null,}) {
  return _then(ActionAnswer(
columns: null == columns ? _self.columns : columns // ignore: cast_nullable_to_non_nullable
as IList<String>,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as IList<IList<String>>,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _ActionAnswer implements ActionAnswer {
  const _ActionAnswer({this.columns = const IListConst([]), this.rows = const IListConst([]), this.count = 0, this.lines = const IListConst([])});
  

/// The records' fields, in the order first seen (at most six).
@override@JsonKey() final  IList<String> columns;
/// One cell per column, as text; empty when the answer is no table.
@override@JsonKey() final  IList<IList<String>> rows;
/// How many rows the action answered.
@override@JsonKey() final  int count;
/// Each row as indented JSON, split into lines.
@override@JsonKey() final  IList<String> lines;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionAnswerCopyWith<_ActionAnswer> get copyWith => __$ActionAnswerCopyWithImpl<_ActionAnswer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionAnswer&&const DeepCollectionEquality().equals(other.columns, columns)&&const DeepCollectionEquality().equals(other.rows, rows)&&(identical(other.count, count) || other.count == count)&&const DeepCollectionEquality().equals(other.lines, lines));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(columns),const DeepCollectionEquality().hash(rows),count,const DeepCollectionEquality().hash(lines));
}

@override
String toString() {
    return 'ActionAnswer(columns: $columns, rows: $rows, count: $count, lines: $lines)';
}


}

/// @nodoc
abstract mixin class _$ActionAnswerCopyWith<$Res> implements $ActionAnswerCopyWith<$Res> {
  factory _$ActionAnswerCopyWith(_ActionAnswer value, $Res Function(_ActionAnswer) _then) = __$ActionAnswerCopyWithImpl;
@override @useResult
$Res call({
 IList<String> columns, IList<IList<String>> rows, int count, IList<String> lines
});




}
/// @nodoc
class __$ActionAnswerCopyWithImpl<$Res>
    implements _$ActionAnswerCopyWith<$Res> {
  __$ActionAnswerCopyWithImpl(this._self, this._then);

  final _ActionAnswer _self;
  final $Res Function(_ActionAnswer) _then;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? columns = null,Object? rows = null,Object? count = null,Object? lines = null,}) {
  return _then(_ActionAnswer(
columns: null == columns ? _self.columns : columns // ignore: cast_nullable_to_non_nullable
as IList<String>,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as IList<IList<String>>,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
