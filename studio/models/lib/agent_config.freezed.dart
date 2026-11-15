// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentConfig {

/// The model the agent asks (`model`).
 String? get model;/// Who approves a plan (`require_approval`); null when not set.
 ApprovalMode? get approval;/// Where it may propose changes (`allowed_prefixes`).
 IList<String> get prefixes;/// Its daily budget of LLM tokens (`budget_tokens_day`).
 int? get budgetTokensDay;/// The name of the secret that holds its API key (`api_key_ref`).
 String? get apiKeyRef;/// Where its requests go (`api_base`).
 String? get apiBase;
/// Create a copy of AgentConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentConfigCopyWith<AgentConfig> get copyWith => _$AgentConfigCopyWithImpl<AgentConfig>(this as AgentConfig, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentConfig&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.approval, _this.approval) || other.approval == _this.approval)&&const DeepCollectionEquality().equals(other.prefixes, _this.prefixes)&&(identical(other.budgetTokensDay, _this.budgetTokensDay) || other.budgetTokensDay == _this.budgetTokensDay)&&(identical(other.apiKeyRef, _this.apiKeyRef) || other.apiKeyRef == _this.apiKeyRef)&&(identical(other.apiBase, _this.apiBase) || other.apiBase == _this.apiBase));
}


@override
int get hashCode {
  final _this = this as AgentConfig;
  return Object.hash(runtimeType,_this.model,_this.approval,const DeepCollectionEquality().hash(_this.prefixes),_this.budgetTokensDay,_this.apiKeyRef,_this.apiBase);
}

@override
String toString() {
  final _this = this as AgentConfig;
  return 'AgentConfig(model: ${_this.model}, approval: ${_this.approval}, prefixes: ${_this.prefixes}, budgetTokensDay: ${_this.budgetTokensDay}, apiKeyRef: ${_this.apiKeyRef}, apiBase: ${_this.apiBase})';
}


}

/// @nodoc
abstract mixin class $AgentConfigCopyWith<$Res>  {
  factory $AgentConfigCopyWith(AgentConfig value, $Res Function(AgentConfig) _then) = _$AgentConfigCopyWithImpl;
@useResult
$Res call({
 String? model, ApprovalMode? approval, IList<String> prefixes, int? budgetTokensDay, String? apiKeyRef, String? apiBase
});




}
/// @nodoc
class _$AgentConfigCopyWithImpl<$Res>
    implements $AgentConfigCopyWith<$Res> {
  _$AgentConfigCopyWithImpl(this._self, this._then);

  final AgentConfig _self;
  final $Res Function(AgentConfig) _then;

/// Create a copy of AgentConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = freezed,Object? approval = freezed,Object? prefixes = null,Object? budgetTokensDay = freezed,Object? apiKeyRef = freezed,Object? apiBase = freezed,}) {
  return _then(AgentConfig(
model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,approval: freezed == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as ApprovalMode?,prefixes: null == prefixes ? _self.prefixes : prefixes // ignore: cast_nullable_to_non_nullable
as IList<String>,budgetTokensDay: freezed == budgetTokensDay ? _self.budgetTokensDay : budgetTokensDay // ignore: cast_nullable_to_non_nullable
as int?,apiKeyRef: freezed == apiKeyRef ? _self.apiKeyRef : apiKeyRef // ignore: cast_nullable_to_non_nullable
as String?,apiBase: freezed == apiBase ? _self.apiBase : apiBase // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _AgentConfig extends AgentConfig {
  const _AgentConfig({this.model, this.approval, this.prefixes = const IListConst([]), this.budgetTokensDay, this.apiKeyRef, this.apiBase}): super._();
  

/// The model the agent asks (`model`).
@override final  String? model;
/// Who approves a plan (`require_approval`); null when not set.
@override final  ApprovalMode? approval;
/// Where it may propose changes (`allowed_prefixes`).
@override@JsonKey() final  IList<String> prefixes;
/// Its daily budget of LLM tokens (`budget_tokens_day`).
@override final  int? budgetTokensDay;
/// The name of the secret that holds its API key (`api_key_ref`).
@override final  String? apiKeyRef;
/// Where its requests go (`api_base`).
@override final  String? apiBase;

/// Create a copy of AgentConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentConfigCopyWith<_AgentConfig> get copyWith => __$AgentConfigCopyWithImpl<_AgentConfig>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentConfig&&(identical(other.model, model) || other.model == model)&&(identical(other.approval, approval) || other.approval == approval)&&const DeepCollectionEquality().equals(other.prefixes, prefixes)&&(identical(other.budgetTokensDay, budgetTokensDay) || other.budgetTokensDay == budgetTokensDay)&&(identical(other.apiKeyRef, apiKeyRef) || other.apiKeyRef == apiKeyRef)&&(identical(other.apiBase, apiBase) || other.apiBase == apiBase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,approval,const DeepCollectionEquality().hash(prefixes),budgetTokensDay,apiKeyRef,apiBase);
}

@override
String toString() {
    return 'AgentConfig(model: $model, approval: $approval, prefixes: $prefixes, budgetTokensDay: $budgetTokensDay, apiKeyRef: $apiKeyRef, apiBase: $apiBase)';
}


}

/// @nodoc
abstract mixin class _$AgentConfigCopyWith<$Res> implements $AgentConfigCopyWith<$Res> {
  factory _$AgentConfigCopyWith(_AgentConfig value, $Res Function(_AgentConfig) _then) = __$AgentConfigCopyWithImpl;
@override @useResult
$Res call({
 String? model, ApprovalMode? approval, IList<String> prefixes, int? budgetTokensDay, String? apiKeyRef, String? apiBase
});




}
/// @nodoc
class __$AgentConfigCopyWithImpl<$Res>
    implements _$AgentConfigCopyWith<$Res> {
  __$AgentConfigCopyWithImpl(this._self, this._then);

  final _AgentConfig _self;
  final $Res Function(_AgentConfig) _then;

/// Create a copy of AgentConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = freezed,Object? approval = freezed,Object? prefixes = null,Object? budgetTokensDay = freezed,Object? apiKeyRef = freezed,Object? apiBase = freezed,}) {
  return _then(_AgentConfig(
model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,approval: freezed == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as ApprovalMode?,prefixes: null == prefixes ? _self.prefixes : prefixes // ignore: cast_nullable_to_non_nullable
as IList<String>,budgetTokensDay: freezed == budgetTokensDay ? _self.budgetTokensDay : budgetTokensDay // ignore: cast_nullable_to_non_nullable
as int?,apiKeyRef: freezed == apiKeyRef ? _self.apiKeyRef : apiKeyRef // ignore: cast_nullable_to_non_nullable
as String?,apiBase: freezed == apiBase ? _self.apiBase : apiBase // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
