// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'approval_refusal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApprovalRefusal {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRefusal);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApprovalRefusal()';
}


}

/// @nodoc
class $ApprovalRefusalCopyWith<$Res>  {
$ApprovalRefusalCopyWith(ApprovalRefusal _, $Res Function(ApprovalRefusal) __);
}



/// @nodoc


class ApprovalRefusalChanged implements ApprovalRefusal {
  const ApprovalRefusalChanged();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRefusalChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApprovalRefusal.changed()';
}


}




/// @nodoc


class ApprovalRefusalUnseen implements ApprovalRefusal {
  const ApprovalRefusalUnseen(this.step);
  

 final  int step;

/// Create a copy of ApprovalRefusal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApprovalRefusalUnseenCopyWith<ApprovalRefusalUnseen> get copyWith => _$ApprovalRefusalUnseenCopyWithImpl<ApprovalRefusalUnseen>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRefusalUnseen&&(identical(other.step, step) || other.step == step));
}


@override
int get hashCode {
    return Object.hash(runtimeType,step);
}

@override
String toString() {
    return 'ApprovalRefusal.unseen(step: $step)';
}


}

/// @nodoc
abstract mixin class $ApprovalRefusalUnseenCopyWith<$Res> implements $ApprovalRefusalCopyWith<$Res> {
  factory $ApprovalRefusalUnseenCopyWith(ApprovalRefusalUnseen value, $Res Function(ApprovalRefusalUnseen) _then) = _$ApprovalRefusalUnseenCopyWithImpl;
@useResult
$Res call({
 int step
});




}
/// @nodoc
class _$ApprovalRefusalUnseenCopyWithImpl<$Res>
    implements $ApprovalRefusalUnseenCopyWith<$Res> {
  _$ApprovalRefusalUnseenCopyWithImpl(this._self, this._then);

  final ApprovalRefusalUnseen _self;
  final $Res Function(ApprovalRefusalUnseen) _then;

/// Create a copy of ApprovalRefusal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? step = null,}) {
  return _then(ApprovalRefusalUnseen(
null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ApprovalRefusalSaid implements ApprovalRefusal {
  const ApprovalRefusalSaid(this.message);
  

 final  String message;

/// Create a copy of ApprovalRefusal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApprovalRefusalSaidCopyWith<ApprovalRefusalSaid> get copyWith => _$ApprovalRefusalSaidCopyWithImpl<ApprovalRefusalSaid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRefusalSaid&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'ApprovalRefusal.said(message: $message)';
}


}

/// @nodoc
abstract mixin class $ApprovalRefusalSaidCopyWith<$Res> implements $ApprovalRefusalCopyWith<$Res> {
  factory $ApprovalRefusalSaidCopyWith(ApprovalRefusalSaid value, $Res Function(ApprovalRefusalSaid) _then) = _$ApprovalRefusalSaidCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ApprovalRefusalSaidCopyWithImpl<$Res>
    implements $ApprovalRefusalSaidCopyWith<$Res> {
  _$ApprovalRefusalSaidCopyWithImpl(this._self, this._then);

  final ApprovalRefusalSaid _self;
  final $Res Function(ApprovalRefusalSaid) _then;

/// Create a copy of ApprovalRefusal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(ApprovalRefusalSaid(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
