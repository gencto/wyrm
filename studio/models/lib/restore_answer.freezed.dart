// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'restore_answer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RestoreAnswer {

 RestoreMode get mode; bool get restart;/// The sections staged (`replace`).
 IList<BackupSection> get sections;/// What was added, in the broker's words (`add`).
 IList<String> get done;/// What was left as it is, with the reason (`add`).
 IList<String> get skipped;
/// Create a copy of RestoreAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestoreAnswerCopyWith<RestoreAnswer> get copyWith => _$RestoreAnswerCopyWithImpl<RestoreAnswer>(this as RestoreAnswer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RestoreAnswer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreAnswer&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.restart, _this.restart) || other.restart == _this.restart)&&const DeepCollectionEquality().equals(other.sections, _this.sections)&&const DeepCollectionEquality().equals(other.done, _this.done)&&const DeepCollectionEquality().equals(other.skipped, _this.skipped));
}


@override
int get hashCode {
  final _this = this as RestoreAnswer;
  return Object.hash(runtimeType,_this.mode,_this.restart,const DeepCollectionEquality().hash(_this.sections),const DeepCollectionEquality().hash(_this.done),const DeepCollectionEquality().hash(_this.skipped));
}

@override
String toString() {
  final _this = this as RestoreAnswer;
  return 'RestoreAnswer(mode: ${_this.mode}, restart: ${_this.restart}, sections: ${_this.sections}, done: ${_this.done}, skipped: ${_this.skipped})';
}


}

/// @nodoc
abstract mixin class $RestoreAnswerCopyWith<$Res>  {
  factory $RestoreAnswerCopyWith(RestoreAnswer value, $Res Function(RestoreAnswer) _then) = _$RestoreAnswerCopyWithImpl;
@useResult
$Res call({
 RestoreMode mode, bool restart, IList<BackupSection> sections, IList<String> done, IList<String> skipped
});




}
/// @nodoc
class _$RestoreAnswerCopyWithImpl<$Res>
    implements $RestoreAnswerCopyWith<$Res> {
  _$RestoreAnswerCopyWithImpl(this._self, this._then);

  final RestoreAnswer _self;
  final $Res Function(RestoreAnswer) _then;

/// Create a copy of RestoreAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? restart = null,Object? sections = null,Object? done = null,Object? skipped = null,}) {
  return _then(RestoreAnswer(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as RestoreMode,restart: null == restart ? _self.restart : restart // ignore: cast_nullable_to_non_nullable
as bool,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as IList<String>,skipped: null == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _RestoreAnswer implements RestoreAnswer {
  const _RestoreAnswer({required this.mode, required this.restart, this.sections = const IListConst([]), this.done = const IListConst([]), this.skipped = const IListConst([])});
  

@override final  RestoreMode mode;
@override final  bool restart;
/// The sections staged (`replace`).
@override@JsonKey() final  IList<BackupSection> sections;
/// What was added, in the broker's words (`add`).
@override@JsonKey() final  IList<String> done;
/// What was left as it is, with the reason (`add`).
@override@JsonKey() final  IList<String> skipped;

/// Create a copy of RestoreAnswer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreAnswerCopyWith<_RestoreAnswer> get copyWith => __$RestoreAnswerCopyWithImpl<_RestoreAnswer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreAnswer&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.restart, restart) || other.restart == restart)&&const DeepCollectionEquality().equals(other.sections, sections)&&const DeepCollectionEquality().equals(other.done, done)&&const DeepCollectionEquality().equals(other.skipped, skipped));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode,restart,const DeepCollectionEquality().hash(sections),const DeepCollectionEquality().hash(done),const DeepCollectionEquality().hash(skipped));
}

@override
String toString() {
    return 'RestoreAnswer(mode: $mode, restart: $restart, sections: $sections, done: $done, skipped: $skipped)';
}


}

/// @nodoc
abstract mixin class _$RestoreAnswerCopyWith<$Res> implements $RestoreAnswerCopyWith<$Res> {
  factory _$RestoreAnswerCopyWith(_RestoreAnswer value, $Res Function(_RestoreAnswer) _then) = __$RestoreAnswerCopyWithImpl;
@override @useResult
$Res call({
 RestoreMode mode, bool restart, IList<BackupSection> sections, IList<String> done, IList<String> skipped
});




}
/// @nodoc
class __$RestoreAnswerCopyWithImpl<$Res>
    implements _$RestoreAnswerCopyWith<$Res> {
  __$RestoreAnswerCopyWithImpl(this._self, this._then);

  final _RestoreAnswer _self;
  final $Res Function(_RestoreAnswer) _then;

/// Create a copy of RestoreAnswer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? restart = null,Object? sections = null,Object? done = null,Object? skipped = null,}) {
  return _then(_RestoreAnswer(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as RestoreMode,restart: null == restart ? _self.restart : restart // ignore: cast_nullable_to_non_nullable
as bool,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as IList<String>,skipped: null == skipped ? _self.skipped : skipped // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
