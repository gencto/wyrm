// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'change_side.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChangeSide {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSide);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ChangeSide()';
}


}

/// @nodoc
class $ChangeSideCopyWith<$Res>  {
$ChangeSideCopyWith(ChangeSide _, $Res Function(ChangeSide) __);
}



/// @nodoc


class ChangeSideText implements ChangeSide {
  const ChangeSideText(this.text);
  

 final  String text;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeSideTextCopyWith<ChangeSideText> get copyWith => _$ChangeSideTextCopyWithImpl<ChangeSideText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'ChangeSide.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $ChangeSideTextCopyWith<$Res> implements $ChangeSideCopyWith<$Res> {
  factory $ChangeSideTextCopyWith(ChangeSideText value, $Res Function(ChangeSideText) _then) = _$ChangeSideTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ChangeSideTextCopyWithImpl<$Res>
    implements $ChangeSideTextCopyWith<$Res> {
  _$ChangeSideTextCopyWithImpl(this._self, this._then);

  final ChangeSideText _self;
  final $Res Function(ChangeSideText) _then;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ChangeSideText(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChangeSideNone implements ChangeSide {
  const ChangeSideNone();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideNone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ChangeSide.none()';
}


}




/// @nodoc


class ChangeSideRev implements ChangeSide {
  const ChangeSideRev(this.rev);
  

 final  int rev;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeSideRevCopyWith<ChangeSideRev> get copyWith => _$ChangeSideRevCopyWithImpl<ChangeSideRev>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideRev&&(identical(other.rev, rev) || other.rev == rev));
}


@override
int get hashCode {
    return Object.hash(runtimeType,rev);
}

@override
String toString() {
    return 'ChangeSide.rev(rev: $rev)';
}


}

/// @nodoc
abstract mixin class $ChangeSideRevCopyWith<$Res> implements $ChangeSideCopyWith<$Res> {
  factory $ChangeSideRevCopyWith(ChangeSideRev value, $Res Function(ChangeSideRev) _then) = _$ChangeSideRevCopyWithImpl;
@useResult
$Res call({
 int rev
});




}
/// @nodoc
class _$ChangeSideRevCopyWithImpl<$Res>
    implements $ChangeSideRevCopyWith<$Res> {
  _$ChangeSideRevCopyWithImpl(this._self, this._then);

  final ChangeSideRev _self;
  final $Res Function(ChangeSideRev) _then;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rev = null,}) {
  return _then(ChangeSideRev(
null == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ChangeSideParams implements ChangeSide {
  const ChangeSideParams(this.values, {this.rev});
  

 final  IList<ParamSide> values;
 final  int? rev;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeSideParamsCopyWith<ChangeSideParams> get copyWith => _$ChangeSideParamsCopyWithImpl<ChangeSideParams>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideParams&&const DeepCollectionEquality().equals(other.values, values)&&(identical(other.rev, rev) || other.rev == rev));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(values),rev);
}

@override
String toString() {
    return 'ChangeSide.params(values: $values, rev: $rev)';
}


}

/// @nodoc
abstract mixin class $ChangeSideParamsCopyWith<$Res> implements $ChangeSideCopyWith<$Res> {
  factory $ChangeSideParamsCopyWith(ChangeSideParams value, $Res Function(ChangeSideParams) _then) = _$ChangeSideParamsCopyWithImpl;
@useResult
$Res call({
 IList<ParamSide> values, int? rev
});




}
/// @nodoc
class _$ChangeSideParamsCopyWithImpl<$Res>
    implements $ChangeSideParamsCopyWith<$Res> {
  _$ChangeSideParamsCopyWithImpl(this._self, this._then);

  final ChangeSideParams _self;
  final $Res Function(ChangeSideParams) _then;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,Object? rev = freezed,}) {
  return _then(ChangeSideParams(
null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IList<ParamSide>,rev: freezed == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ChangeSideFlag implements ChangeSide {
  const ChangeSideFlag({required this.on});
  

 final  bool on;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeSideFlagCopyWith<ChangeSideFlag> get copyWith => _$ChangeSideFlagCopyWithImpl<ChangeSideFlag>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideFlag&&(identical(other.on, on) || other.on == on));
}


@override
int get hashCode {
    return Object.hash(runtimeType,on);
}

@override
String toString() {
    return 'ChangeSide.flag(on: $on)';
}


}

/// @nodoc
abstract mixin class $ChangeSideFlagCopyWith<$Res> implements $ChangeSideCopyWith<$Res> {
  factory $ChangeSideFlagCopyWith(ChangeSideFlag value, $Res Function(ChangeSideFlag) _then) = _$ChangeSideFlagCopyWithImpl;
@useResult
$Res call({
 bool on
});




}
/// @nodoc
class _$ChangeSideFlagCopyWithImpl<$Res>
    implements $ChangeSideFlagCopyWith<$Res> {
  _$ChangeSideFlagCopyWithImpl(this._self, this._then);

  final ChangeSideFlag _self;
  final $Res Function(ChangeSideFlag) _then;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? on = null,}) {
  return _then(ChangeSideFlag(
on: null == on ? _self.on : on // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ChangeSideKeys implements ChangeSide {
  const ChangeSideKeys(this.count);
  

 final  int count;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeSideKeysCopyWith<ChangeSideKeys> get copyWith => _$ChangeSideKeysCopyWithImpl<ChangeSideKeys>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeSideKeys&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode {
    return Object.hash(runtimeType,count);
}

@override
String toString() {
    return 'ChangeSide.keys(count: $count)';
}


}

/// @nodoc
abstract mixin class $ChangeSideKeysCopyWith<$Res> implements $ChangeSideCopyWith<$Res> {
  factory $ChangeSideKeysCopyWith(ChangeSideKeys value, $Res Function(ChangeSideKeys) _then) = _$ChangeSideKeysCopyWithImpl;
@useResult
$Res call({
 int count
});




}
/// @nodoc
class _$ChangeSideKeysCopyWithImpl<$Res>
    implements $ChangeSideKeysCopyWith<$Res> {
  _$ChangeSideKeysCopyWithImpl(this._self, this._then);

  final ChangeSideKeys _self;
  final $Res Function(ChangeSideKeys) _then;

/// Create a copy of ChangeSide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? count = null,}) {
  return _then(ChangeSideKeys(
null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
