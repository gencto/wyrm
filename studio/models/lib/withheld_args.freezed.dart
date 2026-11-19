// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'withheld_args.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WithheldArgs {

 int get step; IList<String> get names;
/// Create a copy of WithheldArgs
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WithheldArgsCopyWith<WithheldArgs> get copyWith => _$WithheldArgsCopyWithImpl<WithheldArgs>(this as WithheldArgs, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WithheldArgs;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WithheldArgs&&(identical(other.step, _this.step) || other.step == _this.step)&&const DeepCollectionEquality().equals(other.names, _this.names));
}


@override
int get hashCode {
  final _this = this as WithheldArgs;
  return Object.hash(runtimeType,_this.step,const DeepCollectionEquality().hash(_this.names));
}

@override
String toString() {
  final _this = this as WithheldArgs;
  return 'WithheldArgs(step: ${_this.step}, names: ${_this.names})';
}


}

/// @nodoc
abstract mixin class $WithheldArgsCopyWith<$Res>  {
  factory $WithheldArgsCopyWith(WithheldArgs value, $Res Function(WithheldArgs) _then) = _$WithheldArgsCopyWithImpl;
@useResult
$Res call({
 int step, IList<String> names
});




}
/// @nodoc
class _$WithheldArgsCopyWithImpl<$Res>
    implements $WithheldArgsCopyWith<$Res> {
  _$WithheldArgsCopyWithImpl(this._self, this._then);

  final WithheldArgs _self;
  final $Res Function(WithheldArgs) _then;

/// Create a copy of WithheldArgs
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? names = null,}) {
  return _then(WithheldArgs(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,names: null == names ? _self.names : names // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _WithheldArgs implements WithheldArgs {
  const _WithheldArgs({required this.step, required this.names});
  

@override final  int step;
@override final  IList<String> names;

/// Create a copy of WithheldArgs
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WithheldArgsCopyWith<_WithheldArgs> get copyWith => __$WithheldArgsCopyWithImpl<_WithheldArgs>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WithheldArgs&&(identical(other.step, step) || other.step == step)&&const DeepCollectionEquality().equals(other.names, names));
}


@override
int get hashCode {
    return Object.hash(runtimeType,step,const DeepCollectionEquality().hash(names));
}

@override
String toString() {
    return 'WithheldArgs(step: $step, names: $names)';
}


}

/// @nodoc
abstract mixin class _$WithheldArgsCopyWith<$Res> implements $WithheldArgsCopyWith<$Res> {
  factory _$WithheldArgsCopyWith(_WithheldArgs value, $Res Function(_WithheldArgs) _then) = __$WithheldArgsCopyWithImpl;
@override @useResult
$Res call({
 int step, IList<String> names
});




}
/// @nodoc
class __$WithheldArgsCopyWithImpl<$Res>
    implements _$WithheldArgsCopyWith<$Res> {
  __$WithheldArgsCopyWithImpl(this._self, this._then);

  final _WithheldArgs _self;
  final $Res Function(_WithheldArgs) _then;

/// Create a copy of WithheldArgs
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? step = null,Object? names = null,}) {
  return _then(_WithheldArgs(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,names: null == names ? _self.names : names // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
