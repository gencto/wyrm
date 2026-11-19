// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'field_label.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FieldLabel {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldLabel);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'FieldLabel()';
}


}

/// @nodoc
class $FieldLabelCopyWith<$Res>  {
$FieldLabelCopyWith(FieldLabel _, $Res Function(FieldLabel) __);
}



/// @nodoc


class FieldLabelText implements FieldLabel {
  const FieldLabelText(this.text);
  

 final  String text;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldLabelTextCopyWith<FieldLabelText> get copyWith => _$FieldLabelTextCopyWithImpl<FieldLabelText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldLabelText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'FieldLabel.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $FieldLabelTextCopyWith<$Res> implements $FieldLabelCopyWith<$Res> {
  factory $FieldLabelTextCopyWith(FieldLabelText value, $Res Function(FieldLabelText) _then) = _$FieldLabelTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$FieldLabelTextCopyWithImpl<$Res>
    implements $FieldLabelTextCopyWith<$Res> {
  _$FieldLabelTextCopyWithImpl(this._self, this._then);

  final FieldLabelText _self;
  final $Res Function(FieldLabelText) _then;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(FieldLabelText(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FieldLabelWord implements FieldLabel {
  const FieldLabelWord(this.word);
  

 final  FieldWord word;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldLabelWordCopyWith<FieldLabelWord> get copyWith => _$FieldLabelWordCopyWithImpl<FieldLabelWord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldLabelWord&&(identical(other.word, word) || other.word == word));
}


@override
int get hashCode {
    return Object.hash(runtimeType,word);
}

@override
String toString() {
    return 'FieldLabel.word(word: $word)';
}


}

/// @nodoc
abstract mixin class $FieldLabelWordCopyWith<$Res> implements $FieldLabelCopyWith<$Res> {
  factory $FieldLabelWordCopyWith(FieldLabelWord value, $Res Function(FieldLabelWord) _then) = _$FieldLabelWordCopyWithImpl;
@useResult
$Res call({
 FieldWord word
});




}
/// @nodoc
class _$FieldLabelWordCopyWithImpl<$Res>
    implements $FieldLabelWordCopyWith<$Res> {
  _$FieldLabelWordCopyWithImpl(this._self, this._then);

  final FieldLabelWord _self;
  final $Res Function(FieldLabelWord) _then;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? word = null,}) {
  return _then(FieldLabelWord(
null == word ? _self.word : word // ignore: cast_nullable_to_non_nullable
as FieldWord,
  ));
}


}

/// @nodoc


class FieldLabelNumbered implements FieldLabel {
  const FieldLabelNumbered(this.word, this.n);
  

 final  FieldWord word;
 final  int n;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldLabelNumberedCopyWith<FieldLabelNumbered> get copyWith => _$FieldLabelNumberedCopyWithImpl<FieldLabelNumbered>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldLabelNumbered&&(identical(other.word, word) || other.word == word)&&(identical(other.n, n) || other.n == n));
}


@override
int get hashCode {
    return Object.hash(runtimeType,word,n);
}

@override
String toString() {
    return 'FieldLabel.numbered(word: $word, n: $n)';
}


}

/// @nodoc
abstract mixin class $FieldLabelNumberedCopyWith<$Res> implements $FieldLabelCopyWith<$Res> {
  factory $FieldLabelNumberedCopyWith(FieldLabelNumbered value, $Res Function(FieldLabelNumbered) _then) = _$FieldLabelNumberedCopyWithImpl;
@useResult
$Res call({
 FieldWord word, int n
});




}
/// @nodoc
class _$FieldLabelNumberedCopyWithImpl<$Res>
    implements $FieldLabelNumberedCopyWith<$Res> {
  _$FieldLabelNumberedCopyWithImpl(this._self, this._then);

  final FieldLabelNumbered _self;
  final $Res Function(FieldLabelNumbered) _then;

/// Create a copy of FieldLabel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? word = null,Object? n = null,}) {
  return _then(FieldLabelNumbered(
null == word ? _self.word : word // ignore: cast_nullable_to_non_nullable
as FieldWord,null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
