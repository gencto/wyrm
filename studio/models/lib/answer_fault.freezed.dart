// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'answer_fault.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AnswerFault {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFault);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AnswerFault()';
}


}

/// @nodoc
class $AnswerFaultCopyWith<$Res>  {
$AnswerFaultCopyWith(AnswerFault _, $Res Function(AnswerFault) __);
}



/// @nodoc


class AnswerFaultTimedOut implements AnswerFault {
  const AnswerFaultTimedOut();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultTimedOut);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AnswerFault.timedOut()';
}


}




/// @nodoc


class AnswerFaultNotGateway implements AnswerFault {
  const AnswerFaultNotGateway();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultNotGateway);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AnswerFault.notGateway()';
}


}




/// @nodoc


class AnswerFaultWrongShape implements AnswerFault {
  const AnswerFaultWrongShape({required this.path, required this.expected, required this.got});
  

 final  String path;
 final  String expected;
 final  String got;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerFaultWrongShapeCopyWith<AnswerFaultWrongShape> get copyWith => _$AnswerFaultWrongShapeCopyWithImpl<AnswerFaultWrongShape>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultWrongShape&&(identical(other.path, path) || other.path == path)&&(identical(other.expected, expected) || other.expected == expected)&&(identical(other.got, got) || other.got == got));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,expected,got);
}

@override
String toString() {
    return 'AnswerFault.wrongShape(path: $path, expected: $expected, got: $got)';
}


}

/// @nodoc
abstract mixin class $AnswerFaultWrongShapeCopyWith<$Res> implements $AnswerFaultCopyWith<$Res> {
  factory $AnswerFaultWrongShapeCopyWith(AnswerFaultWrongShape value, $Res Function(AnswerFaultWrongShape) _then) = _$AnswerFaultWrongShapeCopyWithImpl;
@useResult
$Res call({
 String path, String expected, String got
});




}
/// @nodoc
class _$AnswerFaultWrongShapeCopyWithImpl<$Res>
    implements $AnswerFaultWrongShapeCopyWith<$Res> {
  _$AnswerFaultWrongShapeCopyWithImpl(this._self, this._then);

  final AnswerFaultWrongShape _self;
  final $Res Function(AnswerFaultWrongShape) _then;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? expected = null,Object? got = null,}) {
  return _then(AnswerFaultWrongShape(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,expected: null == expected ? _self.expected : expected // ignore: cast_nullable_to_non_nullable
as String,got: null == got ? _self.got : got // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AnswerFaultUntrusted implements AnswerFault {
  const AnswerFaultUntrusted();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultUntrusted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AnswerFault.untrusted()';
}


}




/// @nodoc


class AnswerFaultRefusedAfter implements AnswerFault {
  const AnswerFaultRefusedAfter(this.ms);
  

 final  int ms;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerFaultRefusedAfterCopyWith<AnswerFaultRefusedAfter> get copyWith => _$AnswerFaultRefusedAfterCopyWithImpl<AnswerFaultRefusedAfter>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultRefusedAfter&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ms);
}

@override
String toString() {
    return 'AnswerFault.refusedAfter(ms: $ms)';
}


}

/// @nodoc
abstract mixin class $AnswerFaultRefusedAfterCopyWith<$Res> implements $AnswerFaultCopyWith<$Res> {
  factory $AnswerFaultRefusedAfterCopyWith(AnswerFaultRefusedAfter value, $Res Function(AnswerFaultRefusedAfter) _then) = _$AnswerFaultRefusedAfterCopyWithImpl;
@useResult
$Res call({
 int ms
});




}
/// @nodoc
class _$AnswerFaultRefusedAfterCopyWithImpl<$Res>
    implements $AnswerFaultRefusedAfterCopyWith<$Res> {
  _$AnswerFaultRefusedAfterCopyWithImpl(this._self, this._then);

  final AnswerFaultRefusedAfter _self;
  final $Res Function(AnswerFaultRefusedAfter) _then;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ms = null,}) {
  return _then(AnswerFaultRefusedAfter(
null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AnswerFaultNoRoute implements AnswerFault {
  const AnswerFaultNoRoute();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultNoRoute);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AnswerFault.noRoute()';
}


}




/// @nodoc


class AnswerFaultHttp implements AnswerFault {
  const AnswerFaultHttp(this.code);
  

 final  int code;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerFaultHttpCopyWith<AnswerFaultHttp> get copyWith => _$AnswerFaultHttpCopyWithImpl<AnswerFaultHttp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultHttp&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code);
}

@override
String toString() {
    return 'AnswerFault.http(code: $code)';
}


}

/// @nodoc
abstract mixin class $AnswerFaultHttpCopyWith<$Res> implements $AnswerFaultCopyWith<$Res> {
  factory $AnswerFaultHttpCopyWith(AnswerFaultHttp value, $Res Function(AnswerFaultHttp) _then) = _$AnswerFaultHttpCopyWithImpl;
@useResult
$Res call({
 int code
});




}
/// @nodoc
class _$AnswerFaultHttpCopyWithImpl<$Res>
    implements $AnswerFaultHttpCopyWith<$Res> {
  _$AnswerFaultHttpCopyWithImpl(this._self, this._then);

  final AnswerFaultHttp _self;
  final $Res Function(AnswerFaultHttp) _then;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(AnswerFaultHttp(
null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AnswerFaultSaid implements AnswerFault {
  const AnswerFaultSaid(this.text);
  

 final  String text;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerFaultSaidCopyWith<AnswerFaultSaid> get copyWith => _$AnswerFaultSaidCopyWithImpl<AnswerFaultSaid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerFaultSaid&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'AnswerFault.said(text: $text)';
}


}

/// @nodoc
abstract mixin class $AnswerFaultSaidCopyWith<$Res> implements $AnswerFaultCopyWith<$Res> {
  factory $AnswerFaultSaidCopyWith(AnswerFaultSaid value, $Res Function(AnswerFaultSaid) _then) = _$AnswerFaultSaidCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AnswerFaultSaidCopyWithImpl<$Res>
    implements $AnswerFaultSaidCopyWith<$Res> {
  _$AnswerFaultSaidCopyWithImpl(this._self, this._then);

  final AnswerFaultSaid _self;
  final $Res Function(AnswerFaultSaid) _then;

/// Create a copy of AnswerFault
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AnswerFaultSaid(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
