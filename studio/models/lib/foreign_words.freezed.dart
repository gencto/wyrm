// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'foreign_words.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ForeignWords {

/// What it says happened.
 String get title;/// What it says beside that; empty when nothing.
 String get detail;
/// Create a copy of ForeignWords
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ForeignWordsCopyWith<ForeignWords> get copyWith => _$ForeignWordsCopyWithImpl<ForeignWords>(this as ForeignWords, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ForeignWords;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ForeignWords&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as ForeignWords;
  return Object.hash(runtimeType,_this.title,_this.detail);
}

@override
String toString() {
  final _this = this as ForeignWords;
  return 'ForeignWords(title: ${_this.title}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $ForeignWordsCopyWith<$Res>  {
  factory $ForeignWordsCopyWith(ForeignWords value, $Res Function(ForeignWords) _then) = _$ForeignWordsCopyWithImpl;
@useResult
$Res call({
 String title, String detail
});




}
/// @nodoc
class _$ForeignWordsCopyWithImpl<$Res>
    implements $ForeignWordsCopyWith<$Res> {
  _$ForeignWordsCopyWithImpl(this._self, this._then);

  final ForeignWords _self;
  final $Res Function(ForeignWords) _then;

/// Create a copy of ForeignWords
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? detail = null,}) {
  return _then(ForeignWords(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _ForeignWords implements ForeignWords {
  const _ForeignWords({required this.title, this.detail = ''});
  

/// What it says happened.
@override final  String title;
/// What it says beside that; empty when nothing.
@override@JsonKey() final  String detail;

/// Create a copy of ForeignWords
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ForeignWordsCopyWith<_ForeignWords> get copyWith => __$ForeignWordsCopyWithImpl<_ForeignWords>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ForeignWords&&(identical(other.title, title) || other.title == title)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,detail);
}

@override
String toString() {
    return 'ForeignWords(title: $title, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$ForeignWordsCopyWith<$Res> implements $ForeignWordsCopyWith<$Res> {
  factory _$ForeignWordsCopyWith(_ForeignWords value, $Res Function(_ForeignWords) _then) = __$ForeignWordsCopyWithImpl;
@override @useResult
$Res call({
 String title, String detail
});




}
/// @nodoc
class __$ForeignWordsCopyWithImpl<$Res>
    implements _$ForeignWordsCopyWith<$Res> {
  __$ForeignWordsCopyWithImpl(this._self, this._then);

  final _ForeignWords _self;
  final $Res Function(_ForeignWords) _then;

/// Create a copy of ForeignWords
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? detail = null,}) {
  return _then(_ForeignWords(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
