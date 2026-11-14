// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_question.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskQuestion {

/// `q1`, `q2`, …: unique in the task.
 String get id; String get text; IList<TaskOption> get options;/// Several options may be picked.
 bool get multiple;/// The person may answer in their own words.
 bool get freeText;/// It was answered (an answer of no option and no words too).
 bool get answered;/// The option ids that were picked.
 IList<String> get picked;/// The person's own words, when the answer was text.
 String? get words;
/// Create a copy of TaskQuestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskQuestionCopyWith<TaskQuestion> get copyWith => _$TaskQuestionCopyWithImpl<TaskQuestion>(this as TaskQuestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskQuestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskQuestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.options, _this.options)&&(identical(other.multiple, _this.multiple) || other.multiple == _this.multiple)&&(identical(other.freeText, _this.freeText) || other.freeText == _this.freeText)&&(identical(other.answered, _this.answered) || other.answered == _this.answered)&&const DeepCollectionEquality().equals(other.picked, _this.picked)&&(identical(other.words, _this.words) || other.words == _this.words));
}


@override
int get hashCode {
  final _this = this as TaskQuestion;
  return Object.hash(runtimeType,_this.id,_this.text,const DeepCollectionEquality().hash(_this.options),_this.multiple,_this.freeText,_this.answered,const DeepCollectionEquality().hash(_this.picked),_this.words);
}

@override
String toString() {
  final _this = this as TaskQuestion;
  return 'TaskQuestion(id: ${_this.id}, text: ${_this.text}, options: ${_this.options}, multiple: ${_this.multiple}, freeText: ${_this.freeText}, answered: ${_this.answered}, picked: ${_this.picked}, words: ${_this.words})';
}


}

/// @nodoc
abstract mixin class $TaskQuestionCopyWith<$Res>  {
  factory $TaskQuestionCopyWith(TaskQuestion value, $Res Function(TaskQuestion) _then) = _$TaskQuestionCopyWithImpl;
@useResult
$Res call({
 String id, String text, IList<TaskOption> options, bool multiple, bool freeText, bool answered, IList<String> picked, String? words
});




}
/// @nodoc
class _$TaskQuestionCopyWithImpl<$Res>
    implements $TaskQuestionCopyWith<$Res> {
  _$TaskQuestionCopyWithImpl(this._self, this._then);

  final TaskQuestion _self;
  final $Res Function(TaskQuestion) _then;

/// Create a copy of TaskQuestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? options = null,Object? multiple = null,Object? freeText = null,Object? answered = null,Object? picked = null,Object? words = freezed,}) {
  return _then(TaskQuestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as IList<TaskOption>,multiple: null == multiple ? _self.multiple : multiple // ignore: cast_nullable_to_non_nullable
as bool,freeText: null == freeText ? _self.freeText : freeText // ignore: cast_nullable_to_non_nullable
as bool,answered: null == answered ? _self.answered : answered // ignore: cast_nullable_to_non_nullable
as bool,picked: null == picked ? _self.picked : picked // ignore: cast_nullable_to_non_nullable
as IList<String>,words: freezed == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _TaskQuestion implements TaskQuestion {
  const _TaskQuestion({required this.id, required this.text, this.options = const IListConst([]), this.multiple = false, this.freeText = false, this.answered = false, this.picked = const IListConst([]), this.words});
  

/// `q1`, `q2`, …: unique in the task.
@override final  String id;
@override final  String text;
@override@JsonKey() final  IList<TaskOption> options;
/// Several options may be picked.
@override@JsonKey() final  bool multiple;
/// The person may answer in their own words.
@override@JsonKey() final  bool freeText;
/// It was answered (an answer of no option and no words too).
@override@JsonKey() final  bool answered;
/// The option ids that were picked.
@override@JsonKey() final  IList<String> picked;
/// The person's own words, when the answer was text.
@override final  String? words;

/// Create a copy of TaskQuestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskQuestionCopyWith<_TaskQuestion> get copyWith => __$TaskQuestionCopyWithImpl<_TaskQuestion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskQuestion&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other.options, options)&&(identical(other.multiple, multiple) || other.multiple == multiple)&&(identical(other.freeText, freeText) || other.freeText == freeText)&&(identical(other.answered, answered) || other.answered == answered)&&const DeepCollectionEquality().equals(other.picked, picked)&&(identical(other.words, words) || other.words == words));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,text,const DeepCollectionEquality().hash(options),multiple,freeText,answered,const DeepCollectionEquality().hash(picked),words);
}

@override
String toString() {
    return 'TaskQuestion(id: $id, text: $text, options: $options, multiple: $multiple, freeText: $freeText, answered: $answered, picked: $picked, words: $words)';
}


}

/// @nodoc
abstract mixin class _$TaskQuestionCopyWith<$Res> implements $TaskQuestionCopyWith<$Res> {
  factory _$TaskQuestionCopyWith(_TaskQuestion value, $Res Function(_TaskQuestion) _then) = __$TaskQuestionCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, IList<TaskOption> options, bool multiple, bool freeText, bool answered, IList<String> picked, String? words
});




}
/// @nodoc
class __$TaskQuestionCopyWithImpl<$Res>
    implements _$TaskQuestionCopyWith<$Res> {
  __$TaskQuestionCopyWithImpl(this._self, this._then);

  final _TaskQuestion _self;
  final $Res Function(_TaskQuestion) _then;

/// Create a copy of TaskQuestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? options = null,Object? multiple = null,Object? freeText = null,Object? answered = null,Object? picked = null,Object? words = freezed,}) {
  return _then(_TaskQuestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as IList<TaskOption>,multiple: null == multiple ? _self.multiple : multiple // ignore: cast_nullable_to_non_nullable
as bool,freeText: null == freeText ? _self.freeText : freeText // ignore: cast_nullable_to_non_nullable
as bool,answered: null == answered ? _self.answered : answered // ignore: cast_nullable_to_non_nullable
as bool,picked: null == picked ? _self.picked : picked // ignore: cast_nullable_to_non_nullable
as IList<String>,words: freezed == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
