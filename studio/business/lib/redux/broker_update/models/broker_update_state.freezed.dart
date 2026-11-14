// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'broker_update_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BrokerUpdateState {

 String? get stage; String get confirm;
/// Create a copy of BrokerUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrokerUpdateStateCopyWith<BrokerUpdateState> get copyWith => _$BrokerUpdateStateCopyWithImpl<BrokerUpdateState>(this as BrokerUpdateState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BrokerUpdateState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrokerUpdateState&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.confirm, _this.confirm) || other.confirm == _this.confirm));
}


@override
int get hashCode {
  final _this = this as BrokerUpdateState;
  return Object.hash(runtimeType,_this.stage,_this.confirm);
}

@override
String toString() {
  final _this = this as BrokerUpdateState;
  return 'BrokerUpdateState(stage: ${_this.stage}, confirm: ${_this.confirm})';
}


}

/// @nodoc
abstract mixin class $BrokerUpdateStateCopyWith<$Res>  {
  factory $BrokerUpdateStateCopyWith(BrokerUpdateState value, $Res Function(BrokerUpdateState) _then) = _$BrokerUpdateStateCopyWithImpl;
@useResult
$Res call({
 String? stage, String confirm
});




}
/// @nodoc
class _$BrokerUpdateStateCopyWithImpl<$Res>
    implements $BrokerUpdateStateCopyWith<$Res> {
  _$BrokerUpdateStateCopyWithImpl(this._self, this._then);

  final BrokerUpdateState _self;
  final $Res Function(BrokerUpdateState) _then;

/// Create a copy of BrokerUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stage = freezed,Object? confirm = null,}) {
  return _then(BrokerUpdateState(
stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,confirm: null == confirm ? _self.confirm : confirm // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _BrokerUpdateState implements BrokerUpdateState {
  const _BrokerUpdateState({this.stage, this.confirm = ''});
  

@override final  String? stage;
@override@JsonKey() final  String confirm;

/// Create a copy of BrokerUpdateState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrokerUpdateStateCopyWith<_BrokerUpdateState> get copyWith => __$BrokerUpdateStateCopyWithImpl<_BrokerUpdateState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrokerUpdateState&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.confirm, confirm) || other.confirm == confirm));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stage,confirm);
}

@override
String toString() {
    return 'BrokerUpdateState(stage: $stage, confirm: $confirm)';
}


}

/// @nodoc
abstract mixin class _$BrokerUpdateStateCopyWith<$Res> implements $BrokerUpdateStateCopyWith<$Res> {
  factory _$BrokerUpdateStateCopyWith(_BrokerUpdateState value, $Res Function(_BrokerUpdateState) _then) = __$BrokerUpdateStateCopyWithImpl;
@override @useResult
$Res call({
 String? stage, String confirm
});




}
/// @nodoc
class __$BrokerUpdateStateCopyWithImpl<$Res>
    implements _$BrokerUpdateStateCopyWith<$Res> {
  __$BrokerUpdateStateCopyWithImpl(this._self, this._then);

  final _BrokerUpdateState _self;
  final $Res Function(_BrokerUpdateState) _then;

/// Create a copy of BrokerUpdateState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stage = freezed,Object? confirm = null,}) {
  return _then(_BrokerUpdateState(
stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,confirm: null == confirm ? _self.confirm : confirm // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
