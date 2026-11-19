// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stated.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Stated<T> {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Stated<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Stated<$T>()';
}


}

/// @nodoc
class $StatedCopyWith<T,$Res>  {
$StatedCopyWith(Stated<T> _, $Res Function(Stated<T>) __);
}



/// @nodoc


class StatedGiven<T> extends Stated<T> {
  const StatedGiven(this.value): super._();
  

 final  T value;

/// Create a copy of Stated
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatedGivenCopyWith<T, StatedGiven<T>> get copyWith => _$StatedGivenCopyWithImpl<T, StatedGiven<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StatedGiven<T>&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value));
}

@override
String toString() {
    return 'Stated<$T>.given(value: $value)';
}


}

/// @nodoc
abstract mixin class $StatedGivenCopyWith<T,$Res> implements $StatedCopyWith<T, $Res> {
  factory $StatedGivenCopyWith(StatedGiven<T> value, $Res Function(StatedGiven<T>) _then) = _$StatedGivenCopyWithImpl;
@useResult
$Res call({
 T value
});




}
/// @nodoc
class _$StatedGivenCopyWithImpl<T,$Res>
    implements $StatedGivenCopyWith<T, $Res> {
  _$StatedGivenCopyWithImpl(this._self, this._then);

  final StatedGiven<T> _self;
  final $Res Function(StatedGiven<T>) _then;

/// Create a copy of Stated
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(StatedGiven<T>(
freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class StatedAbsent<T> extends Stated<T> {
  const StatedAbsent(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StatedAbsent<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Stated<$T>.absent()';
}


}




/// @nodoc


class StatedWrong<T> extends Stated<T> {
  const StatedWrong(this.text): super._();
  

 final  String text;

/// Create a copy of Stated
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatedWrongCopyWith<T, StatedWrong<T>> get copyWith => _$StatedWrongCopyWithImpl<T, StatedWrong<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StatedWrong<T>&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'Stated<$T>.wrong(text: $text)';
}


}

/// @nodoc
abstract mixin class $StatedWrongCopyWith<T,$Res> implements $StatedCopyWith<T, $Res> {
  factory $StatedWrongCopyWith(StatedWrong<T> value, $Res Function(StatedWrong<T>) _then) = _$StatedWrongCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$StatedWrongCopyWithImpl<T,$Res>
    implements $StatedWrongCopyWith<T, $Res> {
  _$StatedWrongCopyWithImpl(this._self, this._then);

  final StatedWrong<T> _self;
  final $Res Function(StatedWrong<T>) _then;

/// Create a copy of Stated
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(StatedWrong<T>(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
