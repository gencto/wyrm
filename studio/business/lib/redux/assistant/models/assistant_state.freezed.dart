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

 String? get draft; String get panel; String? get agent; IMap<String, String> get cfg; bool get docs; IMap<String, ISet<int>> get unticked; IMap<String, String> get refusals; IMap<String, ISet<String>> get picks; bool get shown; IList<String> get watched; IMap<String, ISet<String>> get rowPicks; IList<String> get chips; IMap<String, ISet<int>> get revealed; bool get drawer; IList<String> get prefixes; ISet<String>? get secrets; String? get timelineKey; IList<AuditEntry> get timelineAudit;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AssistantState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.panel, _this.panel) || other.panel == _this.panel)&&(identical(other.agent, _this.agent) || other.agent == _this.agent)&&(identical(other.cfg, _this.cfg) || other.cfg == _this.cfg)&&(identical(other.docs, _this.docs) || other.docs == _this.docs)&&(identical(other.unticked, _this.unticked) || other.unticked == _this.unticked)&&(identical(other.refusals, _this.refusals) || other.refusals == _this.refusals)&&(identical(other.picks, _this.picks) || other.picks == _this.picks)&&(identical(other.shown, _this.shown) || other.shown == _this.shown)&&const DeepCollectionEquality().equals(other.watched, _this.watched)&&(identical(other.rowPicks, _this.rowPicks) || other.rowPicks == _this.rowPicks)&&const DeepCollectionEquality().equals(other.chips, _this.chips)&&(identical(other.revealed, _this.revealed) || other.revealed == _this.revealed)&&(identical(other.drawer, _this.drawer) || other.drawer == _this.drawer)&&const DeepCollectionEquality().equals(other.prefixes, _this.prefixes)&&const DeepCollectionEquality().equals(other.secrets, _this.secrets)&&(identical(other.timelineKey, _this.timelineKey) || other.timelineKey == _this.timelineKey)&&const DeepCollectionEquality().equals(other.timelineAudit, _this.timelineAudit));
}


@override
int get hashCode {
  final _this = this as AssistantState;
  return Object.hash(runtimeType,_this.draft,_this.panel,_this.agent,_this.cfg,_this.docs,_this.unticked,_this.refusals,_this.picks,_this.shown,const DeepCollectionEquality().hash(_this.watched),_this.rowPicks,const DeepCollectionEquality().hash(_this.chips),_this.revealed,_this.drawer,const DeepCollectionEquality().hash(_this.prefixes),const DeepCollectionEquality().hash(_this.secrets),_this.timelineKey,const DeepCollectionEquality().hash(_this.timelineAudit));
}

@override
String toString() {
  final _this = this as AssistantState;
  return 'AssistantState(draft: ${_this.draft}, panel: ${_this.panel}, agent: ${_this.agent}, cfg: ${_this.cfg}, docs: ${_this.docs}, unticked: ${_this.unticked}, refusals: ${_this.refusals}, picks: ${_this.picks}, shown: ${_this.shown}, watched: ${_this.watched}, rowPicks: ${_this.rowPicks}, chips: ${_this.chips}, revealed: ${_this.revealed}, drawer: ${_this.drawer}, prefixes: ${_this.prefixes}, secrets: ${_this.secrets}, timelineKey: ${_this.timelineKey}, timelineAudit: ${_this.timelineAudit})';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals, IMap<String, ISet<String>> picks, bool shown, IList<String> watched, IMap<String, ISet<String>> rowPicks, IList<String> chips, IMap<String, ISet<int>> revealed, bool drawer, IList<String> prefixes, ISet<String>? secrets, String? timelineKey, IList<AuditEntry> timelineAudit
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
@pragma('vm:prefer-inline') @override $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,Object? docs = null,Object? unticked = null,Object? refusals = null,Object? picks = null,Object? shown = null,Object? watched = null,Object? rowPicks = null,Object? chips = null,Object? revealed = null,Object? drawer = null,Object? prefixes = null,Object? secrets = freezed,Object? timelineKey = freezed,Object? timelineAudit = null,}) {
  return _then(AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,picks: null == picks ? _self.picks : picks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IList<String>,rowPicks: null == rowPicks ? _self.rowPicks : rowPicks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,chips: null == chips ? _self.chips : chips // ignore: cast_nullable_to_non_nullable
as IList<String>,revealed: null == revealed ? _self.revealed : revealed // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,drawer: null == drawer ? _self.drawer : drawer // ignore: cast_nullable_to_non_nullable
as bool,prefixes: null == prefixes ? _self.prefixes : prefixes // ignore: cast_nullable_to_non_nullable
as IList<String>,secrets: freezed == secrets ? _self.secrets : secrets // ignore: cast_nullable_to_non_nullable
as ISet<String>?,timelineKey: freezed == timelineKey ? _self.timelineKey : timelineKey // ignore: cast_nullable_to_non_nullable
as String?,timelineAudit: null == timelineAudit ? _self.timelineAudit : timelineAudit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,
  ));
}

}



/// @nodoc


class _AssistantState implements AssistantState {
  const _AssistantState({this.draft, this.panel = 'task', this.agent, this.cfg = const IMapConst({}), this.docs = true, this.unticked = const IMapConst({}), this.refusals = const IMapConst({}), this.picks = const IMapConst({}), this.shown = false, this.watched = const IListConst([]), this.rowPicks = const IMapConst({}), this.chips = const IListConst([]), this.revealed = const IMapConst({}), this.drawer = false, this.prefixes = const IListConst([]), this.secrets, this.timelineKey, this.timelineAudit = const IListConst([])});
  

@override final  String? draft;
@override@JsonKey() final  String panel;
@override final  String? agent;
@override@JsonKey() final  IMap<String, String> cfg;
@override@JsonKey() final  bool docs;
@override@JsonKey() final  IMap<String, ISet<int>> unticked;
@override@JsonKey() final  IMap<String, String> refusals;
@override@JsonKey() final  IMap<String, ISet<String>> picks;
@override@JsonKey() final  bool shown;
@override@JsonKey() final  IList<String> watched;
@override@JsonKey() final  IMap<String, ISet<String>> rowPicks;
@override@JsonKey() final  IList<String> chips;
@override@JsonKey() final  IMap<String, ISet<int>> revealed;
@override@JsonKey() final  bool drawer;
@override@JsonKey() final  IList<String> prefixes;
@override final  ISet<String>? secrets;
@override final  String? timelineKey;
@override@JsonKey() final  IList<AuditEntry> timelineAudit;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantStateCopyWith<_AssistantState> get copyWith => __$AssistantStateCopyWithImpl<_AssistantState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.agent, agent) || other.agent == agent)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.docs, docs) || other.docs == docs)&&(identical(other.unticked, unticked) || other.unticked == unticked)&&(identical(other.refusals, refusals) || other.refusals == refusals)&&(identical(other.picks, picks) || other.picks == picks)&&(identical(other.shown, shown) || other.shown == shown)&&const DeepCollectionEquality().equals(other.watched, watched)&&(identical(other.rowPicks, rowPicks) || other.rowPicks == rowPicks)&&const DeepCollectionEquality().equals(other.chips, chips)&&(identical(other.revealed, revealed) || other.revealed == revealed)&&(identical(other.drawer, drawer) || other.drawer == drawer)&&const DeepCollectionEquality().equals(other.prefixes, prefixes)&&const DeepCollectionEquality().equals(other.secrets, secrets)&&(identical(other.timelineKey, timelineKey) || other.timelineKey == timelineKey)&&const DeepCollectionEquality().equals(other.timelineAudit, timelineAudit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draft,panel,agent,cfg,docs,unticked,refusals,picks,shown,const DeepCollectionEquality().hash(watched),rowPicks,const DeepCollectionEquality().hash(chips),revealed,drawer,const DeepCollectionEquality().hash(prefixes),const DeepCollectionEquality().hash(secrets),timelineKey,const DeepCollectionEquality().hash(timelineAudit));
}

@override
String toString() {
    return 'AssistantState(draft: $draft, panel: $panel, agent: $agent, cfg: $cfg, docs: $docs, unticked: $unticked, refusals: $refusals, picks: $picks, shown: $shown, watched: $watched, rowPicks: $rowPicks, chips: $chips, revealed: $revealed, drawer: $drawer, prefixes: $prefixes, secrets: $secrets, timelineKey: $timelineKey, timelineAudit: $timelineAudit)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 String? draft, String panel, String? agent, IMap<String, String> cfg, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals, IMap<String, ISet<String>> picks, bool shown, IList<String> watched, IMap<String, ISet<String>> rowPicks, IList<String> chips, IMap<String, ISet<int>> revealed, bool drawer, IList<String> prefixes, ISet<String>? secrets, String? timelineKey, IList<AuditEntry> timelineAudit
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
@override @pragma('vm:prefer-inline') $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? cfg = null,Object? docs = null,Object? unticked = null,Object? refusals = null,Object? picks = null,Object? shown = null,Object? watched = null,Object? rowPicks = null,Object? chips = null,Object? revealed = null,Object? drawer = null,Object? prefixes = null,Object? secrets = freezed,Object? timelineKey = freezed,Object? timelineAudit = null,}) {
  return _then(_AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,picks: null == picks ? _self.picks : picks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IList<String>,rowPicks: null == rowPicks ? _self.rowPicks : rowPicks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,chips: null == chips ? _self.chips : chips // ignore: cast_nullable_to_non_nullable
as IList<String>,revealed: null == revealed ? _self.revealed : revealed // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,drawer: null == drawer ? _self.drawer : drawer // ignore: cast_nullable_to_non_nullable
as bool,prefixes: null == prefixes ? _self.prefixes : prefixes // ignore: cast_nullable_to_non_nullable
as IList<String>,secrets: freezed == secrets ? _self.secrets : secrets // ignore: cast_nullable_to_non_nullable
as ISet<String>?,timelineKey: freezed == timelineKey ? _self.timelineKey : timelineKey // ignore: cast_nullable_to_non_nullable
as String?,timelineAudit: null == timelineAudit ? _self.timelineAudit : timelineAudit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,
  ));
}


}

// dart format on
