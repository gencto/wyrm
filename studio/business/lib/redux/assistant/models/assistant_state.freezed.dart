// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assistant_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AssistantState {

 String? get draft; String get panel; String? get agent; IMap<String, String> get cfg;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.agent, agent) || other.agent == agent)&&(identical(other.cfg, cfg) || other.cfg == cfg));
}


@override
int get hashCode => Object.hash(runtimeType,draft,panel,agent,cfg);

@override
String toString() {
  return 'AssistantState(draft: $draft, panel: $panel, agent: $agent, cfg: $cfg)';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg
});




}
/// @nodoc
class _$AssistantStateCopyWithImpl<$Res>
    implements $AssistantStateCopyWith<$Res> {
  _$AssistantStateCopyWithImpl(this._self, this._then);

  final AssistantState _self;
  final $Res Function(AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,}) {
  return _then(_self.copyWith(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}

}



/// @nodoc


class _AssistantState implements AssistantState {
  const _AssistantState({this.draft, this.panel = 'task', this.agent, this.cfg = const IMapConst({})});
  

@override final  String? draft;
@override@JsonKey() final  String panel;
@override final  String? agent;
@override@JsonKey() final  IMap<String, String> cfg;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantStateCopyWith<_AssistantState> get copyWith => __$AssistantStateCopyWithImpl<_AssistantState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.agent, agent) || other.agent == agent)&&(identical(other.cfg, cfg) || other.cfg == cfg));
}


@override
int get hashCode => Object.hash(runtimeType,draft,panel,agent,cfg);

@override
String toString() {
  return 'AssistantState(draft: $draft, panel: $panel, agent: $agent, cfg: $cfg)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg
});




}
/// @nodoc
class __$AssistantStateCopyWithImpl<$Res>
    implements _$AssistantStateCopyWith<$Res> {
  __$AssistantStateCopyWithImpl(this._self, this._then);

  final _AssistantState _self;
  final $Res Function(_AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,}) {
  return _then(_AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}


}

// dart format on
