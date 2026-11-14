// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assistant_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AssistantState {

 String? get draft; String get panel; String? get agent; IMap<String, String> get cfg; bool get docs; IMap<String, ISet<int>> get unticked; IMap<String, String> get refusals;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AssistantState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.panel, _this.panel) || other.panel == _this.panel)&&(identical(other.agent, _this.agent) || other.agent == _this.agent)&&(identical(other.cfg, _this.cfg) || other.cfg == _this.cfg)&&(identical(other.docs, _this.docs) || other.docs == _this.docs)&&(identical(other.unticked, _this.unticked) || other.unticked == _this.unticked)&&(identical(other.refusals, _this.refusals) || other.refusals == _this.refusals));
}


@override
int get hashCode {
  final _this = this as AssistantState;
  return Object.hash(runtimeType,_this.draft,_this.panel,_this.agent,_this.cfg,_this.docs,_this.unticked,_this.refusals);
}

@override
String toString() {
  final _this = this as AssistantState;
  return 'AssistantState(draft: ${_this.draft}, panel: ${_this.panel}, agent: ${_this.agent}, cfg: ${_this.cfg}, docs: ${_this.docs}, unticked: ${_this.unticked}, refusals: ${_this.refusals})';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals
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
@pragma('vm:prefer-inline') @override $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,Object? docs = null,Object? unticked = null,Object? refusals = null,}) {
  return _then(AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}

}



/// @nodoc


class _AssistantState implements AssistantState {
  const _AssistantState({this.draft, this.panel = 'task', this.agent, this.cfg = const IMapConst({}), this.docs = true, this.unticked = const IMapConst({}), this.refusals = const IMapConst({})});
  

@override final  String? draft;
@override@JsonKey() final  String panel;
@override final  String? agent;
@override@JsonKey() final  IMap<String, String> cfg;
@override@JsonKey() final  bool docs;
@override@JsonKey() final  IMap<String, ISet<int>> unticked;
@override@JsonKey() final  IMap<String, String> refusals;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantStateCopyWith<_AssistantState> get copyWith => __$AssistantStateCopyWithImpl<_AssistantState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.agent, agent) || other.agent == agent)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.docs, docs) || other.docs == docs)&&(identical(other.unticked, unticked) || other.unticked == unticked)&&(identical(other.refusals, refusals) || other.refusals == refusals));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draft,panel,agent,cfg,docs,unticked,refusals);
}

@override
String toString() {
    return 'AssistantState(draft: $draft, panel: $panel, agent: $agent, cfg: $cfg, docs: $docs, unticked: $unticked, refusals: $refusals)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals
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
@override @pragma('vm:prefer-inline') $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,Object? docs = null,Object? unticked = null,Object? refusals = null,}) {
  return _then(_AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}


}

// dart format on
