// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_params.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentParams {

/// `require_approval`; null when the params do not set it.
 ApprovalMode? get requireApproval;/// `allowed_prefixes`; null when the params do not set it.
 IList<String>? get allowedPrefixes;/// Every other param, as the link has it (plain JSON values: the screen
/// shows and edits none of them).
 IMap<String, Object?> get others;
/// Create a copy of AgentParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentParamsCopyWith<AgentParams> get copyWith => _$AgentParamsCopyWithImpl<AgentParams>(this as AgentParams, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentParams;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentParams&&(identical(other.requireApproval, _this.requireApproval) || other.requireApproval == _this.requireApproval)&&const DeepCollectionEquality().equals(other.allowedPrefixes, _this.allowedPrefixes)&&(identical(other.others, _this.others) || other.others == _this.others));
}


@override
int get hashCode {
  final _this = this as AgentParams;
  return Object.hash(runtimeType,_this.requireApproval,const DeepCollectionEquality().hash(_this.allowedPrefixes),_this.others);
}

@override
String toString() {
  final _this = this as AgentParams;
  return 'AgentParams(requireApproval: ${_this.requireApproval}, allowedPrefixes: ${_this.allowedPrefixes}, others: ${_this.others})';
}


}

/// @nodoc
abstract mixin class $AgentParamsCopyWith<$Res>  {
  factory $AgentParamsCopyWith(AgentParams value, $Res Function(AgentParams) _then) = _$AgentParamsCopyWithImpl;
@useResult
$Res call({
 ApprovalMode? requireApproval, IList<String>? allowedPrefixes, IMap<String, Object?> others
});




}
/// @nodoc
class _$AgentParamsCopyWithImpl<$Res>
    implements $AgentParamsCopyWith<$Res> {
  _$AgentParamsCopyWithImpl(this._self, this._then);

  final AgentParams _self;
  final $Res Function(AgentParams) _then;

/// Create a copy of AgentParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requireApproval = freezed,Object? allowedPrefixes = freezed,Object? others = null,}) {
  return _then(AgentParams(
requireApproval: freezed == requireApproval ? _self.requireApproval : requireApproval // ignore: cast_nullable_to_non_nullable
as ApprovalMode?,allowedPrefixes: freezed == allowedPrefixes ? _self.allowedPrefixes : allowedPrefixes // ignore: cast_nullable_to_non_nullable
as IList<String>?,others: null == others ? _self.others : others // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}

}



/// @nodoc


class _AgentParams implements AgentParams {
  const _AgentParams({this.requireApproval, this.allowedPrefixes, this.others = const IMapConst({})});
  

/// `require_approval`; null when the params do not set it.
@override final  ApprovalMode? requireApproval;
/// `allowed_prefixes`; null when the params do not set it.
@override final  IList<String>? allowedPrefixes;
/// Every other param, as the link has it (plain JSON values: the screen
/// shows and edits none of them).
@override@JsonKey() final  IMap<String, Object?> others;

/// Create a copy of AgentParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentParamsCopyWith<_AgentParams> get copyWith => __$AgentParamsCopyWithImpl<_AgentParams>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentParams&&(identical(other.requireApproval, requireApproval) || other.requireApproval == requireApproval)&&const DeepCollectionEquality().equals(other.allowedPrefixes, allowedPrefixes)&&(identical(other.others, others) || other.others == others));
}


@override
int get hashCode {
    return Object.hash(runtimeType,requireApproval,const DeepCollectionEquality().hash(allowedPrefixes),others);
}

@override
String toString() {
    return 'AgentParams(requireApproval: $requireApproval, allowedPrefixes: $allowedPrefixes, others: $others)';
}


}

/// @nodoc
abstract mixin class _$AgentParamsCopyWith<$Res> implements $AgentParamsCopyWith<$Res> {
  factory _$AgentParamsCopyWith(_AgentParams value, $Res Function(_AgentParams) _then) = __$AgentParamsCopyWithImpl;
@override @useResult
$Res call({
 ApprovalMode? requireApproval, IList<String>? allowedPrefixes, IMap<String, Object?> others
});




}
/// @nodoc
class __$AgentParamsCopyWithImpl<$Res>
    implements _$AgentParamsCopyWith<$Res> {
  __$AgentParamsCopyWithImpl(this._self, this._then);

  final _AgentParams _self;
  final $Res Function(_AgentParams) _then;

/// Create a copy of AgentParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requireApproval = freezed,Object? allowedPrefixes = freezed,Object? others = null,}) {
  return _then(_AgentParams(
requireApproval: freezed == requireApproval ? _self.requireApproval : requireApproval // ignore: cast_nullable_to_non_nullable
as ApprovalMode?,allowedPrefixes: freezed == allowedPrefixes ? _self.allowedPrefixes : allowedPrefixes // ignore: cast_nullable_to_non_nullable
as IList<String>?,others: null == others ? _self.others : others // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}


}

// dart format on
