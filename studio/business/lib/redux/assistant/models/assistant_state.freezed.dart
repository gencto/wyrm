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

 String? get draft; AssistantPanel get panel; String? get agent;/// What the agent may do, from its root `cfg`; null until it is read
/// (or when its meta is not readable).
 AgentConfig? get config;/// The agent's `cfg` was read and is not one Studio reads (a setting of
/// another type, a mode the link does not have): what it may do, and
/// so who approves, is not known.
 bool get configInvalid; bool get docs; IMap<String, ISet<int>> get unticked; IMap<String, String> get refusals; IMap<String, ISet<String>> get picks; bool get shown; IList<String> get watched; IMap<String, ISet<String>> get rowPicks; IList<String> get chips; IMap<String, ISet<int>> get revealed; bool get drawer;/// The finding nodes the drawer watches while it is shown (its own
/// readers, apart from [watched]); empty while it is hidden.
 IList<String> get drawerWatched;/// The drawer is on screen (Explorer's tab active, the drawer open).
 bool get drawerShown; ISet<String>? get secrets; String? get timelineKey; IList<AuditEntry> get timelineAudit;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AssistantState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.panel, _this.panel) || other.panel == _this.panel)&&(identical(other.agent, _this.agent) || other.agent == _this.agent)&&(identical(other.config, _this.config) || other.config == _this.config)&&(identical(other.configInvalid, _this.configInvalid) || other.configInvalid == _this.configInvalid)&&(identical(other.docs, _this.docs) || other.docs == _this.docs)&&(identical(other.unticked, _this.unticked) || other.unticked == _this.unticked)&&(identical(other.refusals, _this.refusals) || other.refusals == _this.refusals)&&(identical(other.picks, _this.picks) || other.picks == _this.picks)&&(identical(other.shown, _this.shown) || other.shown == _this.shown)&&const DeepCollectionEquality().equals(other.watched, _this.watched)&&(identical(other.rowPicks, _this.rowPicks) || other.rowPicks == _this.rowPicks)&&const DeepCollectionEquality().equals(other.chips, _this.chips)&&(identical(other.revealed, _this.revealed) || other.revealed == _this.revealed)&&(identical(other.drawer, _this.drawer) || other.drawer == _this.drawer)&&const DeepCollectionEquality().equals(other.drawerWatched, _this.drawerWatched)&&(identical(other.drawerShown, _this.drawerShown) || other.drawerShown == _this.drawerShown)&&const DeepCollectionEquality().equals(other.secrets, _this.secrets)&&(identical(other.timelineKey, _this.timelineKey) || other.timelineKey == _this.timelineKey)&&const DeepCollectionEquality().equals(other.timelineAudit, _this.timelineAudit));
}


@override
int get hashCode {
  final _this = this as AssistantState;
  return Object.hashAll([runtimeType,_this.draft,_this.panel,_this.agent,_this.config,_this.configInvalid,_this.docs,_this.unticked,_this.refusals,_this.picks,_this.shown,const DeepCollectionEquality().hash(_this.watched),_this.rowPicks,const DeepCollectionEquality().hash(_this.chips),_this.revealed,_this.drawer,const DeepCollectionEquality().hash(_this.drawerWatched),_this.drawerShown,const DeepCollectionEquality().hash(_this.secrets),_this.timelineKey,const DeepCollectionEquality().hash(_this.timelineAudit)]);
}

@override
String toString() {
  final _this = this as AssistantState;
  return 'AssistantState(draft: ${_this.draft}, panel: ${_this.panel}, agent: ${_this.agent}, config: ${_this.config}, configInvalid: ${_this.configInvalid}, docs: ${_this.docs}, unticked: ${_this.unticked}, refusals: ${_this.refusals}, picks: ${_this.picks}, shown: ${_this.shown}, watched: ${_this.watched}, rowPicks: ${_this.rowPicks}, chips: ${_this.chips}, revealed: ${_this.revealed}, drawer: ${_this.drawer}, drawerWatched: ${_this.drawerWatched}, drawerShown: ${_this.drawerShown}, secrets: ${_this.secrets}, timelineKey: ${_this.timelineKey}, timelineAudit: ${_this.timelineAudit})';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 String? draft, AssistantPanel panel, String? agent, AgentConfig? config, bool configInvalid, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals, IMap<String, ISet<String>> picks, bool shown, IList<String> watched, IMap<String, ISet<String>> rowPicks, IList<String> chips, IMap<String, ISet<int>> revealed, bool drawer, IList<String> drawerWatched, bool drawerShown, ISet<String>? secrets, String? timelineKey, IList<AuditEntry> timelineAudit
});


$AgentConfigCopyWith<$Res>? get config;

}
/// @nodoc
class _$AssistantStateCopyWithImpl<$Res>
    implements $AssistantStateCopyWith<$Res> {
  _$AssistantStateCopyWithImpl(this._self, this._then);

  final AssistantState _self;
  final $Res Function(AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? config = freezed,Object? configInvalid = null,Object? docs = null,Object? unticked = null,Object? refusals = null,Object? picks = null,Object? shown = null,Object? watched = null,Object? rowPicks = null,Object? chips = null,Object? revealed = null,Object? drawer = null,Object? drawerWatched = null,Object? drawerShown = null,Object? secrets = freezed,Object? timelineKey = freezed,Object? timelineAudit = null,}) {
  return _then(AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as AssistantPanel,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,config: freezed == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as AgentConfig?,configInvalid: null == configInvalid ? _self.configInvalid : configInvalid // ignore: cast_nullable_to_non_nullable
as bool,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,picks: null == picks ? _self.picks : picks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IList<String>,rowPicks: null == rowPicks ? _self.rowPicks : rowPicks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,chips: null == chips ? _self.chips : chips // ignore: cast_nullable_to_non_nullable
as IList<String>,revealed: null == revealed ? _self.revealed : revealed // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,drawer: null == drawer ? _self.drawer : drawer // ignore: cast_nullable_to_non_nullable
as bool,drawerWatched: null == drawerWatched ? _self.drawerWatched : drawerWatched // ignore: cast_nullable_to_non_nullable
as IList<String>,drawerShown: null == drawerShown ? _self.drawerShown : drawerShown // ignore: cast_nullable_to_non_nullable
as bool,secrets: freezed == secrets ? _self.secrets : secrets // ignore: cast_nullable_to_non_nullable
as ISet<String>?,timelineKey: freezed == timelineKey ? _self.timelineKey : timelineKey // ignore: cast_nullable_to_non_nullable
as String?,timelineAudit: null == timelineAudit ? _self.timelineAudit : timelineAudit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,
  ));
}
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentConfigCopyWith<$Res>? get config {
    if (_self.config == null) {
    return null;
  }

  return $AgentConfigCopyWith<$Res>(_self.config!, (value) {
    return _then(_self.copyWith(config: value));
  });
}
}



/// @nodoc


class _AssistantState implements AssistantState {
  const _AssistantState({this.draft, this.panel = AssistantPanel.task, this.agent, this.config, this.configInvalid = false, this.docs = true, this.unticked = const IMapConst({}), this.refusals = const IMapConst({}), this.picks = const IMapConst({}), this.shown = false, this.watched = const IListConst([]), this.rowPicks = const IMapConst({}), this.chips = const IListConst([]), this.revealed = const IMapConst({}), this.drawer = false, this.drawerWatched = const IListConst([]), this.drawerShown = false, this.secrets, this.timelineKey, this.timelineAudit = const IListConst([])});
  

@override final  String? draft;
@override@JsonKey() final  AssistantPanel panel;
@override final  String? agent;
/// What the agent may do, from its root `cfg`; null until it is read
/// (or when its meta is not readable).
@override final  AgentConfig? config;
/// The agent's `cfg` was read and is not one Studio reads (a setting of
/// another type, a mode the link does not have): what it may do, and
/// so who approves, is not known.
@override@JsonKey() final  bool configInvalid;
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
/// The finding nodes the drawer watches while it is shown (its own
/// readers, apart from [watched]); empty while it is hidden.
@override@JsonKey() final  IList<String> drawerWatched;
/// The drawer is on screen (Explorer's tab active, the drawer open).
@override@JsonKey() final  bool drawerShown;
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.agent, agent) || other.agent == agent)&&(identical(other.config, config) || other.config == config)&&(identical(other.configInvalid, configInvalid) || other.configInvalid == configInvalid)&&(identical(other.docs, docs) || other.docs == docs)&&(identical(other.unticked, unticked) || other.unticked == unticked)&&(identical(other.refusals, refusals) || other.refusals == refusals)&&(identical(other.picks, picks) || other.picks == picks)&&(identical(other.shown, shown) || other.shown == shown)&&const DeepCollectionEquality().equals(other.watched, watched)&&(identical(other.rowPicks, rowPicks) || other.rowPicks == rowPicks)&&const DeepCollectionEquality().equals(other.chips, chips)&&(identical(other.revealed, revealed) || other.revealed == revealed)&&(identical(other.drawer, drawer) || other.drawer == drawer)&&const DeepCollectionEquality().equals(other.drawerWatched, drawerWatched)&&(identical(other.drawerShown, drawerShown) || other.drawerShown == drawerShown)&&const DeepCollectionEquality().equals(other.secrets, secrets)&&(identical(other.timelineKey, timelineKey) || other.timelineKey == timelineKey)&&const DeepCollectionEquality().equals(other.timelineAudit, timelineAudit));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,draft,panel,agent,config,configInvalid,docs,unticked,refusals,picks,shown,const DeepCollectionEquality().hash(watched),rowPicks,const DeepCollectionEquality().hash(chips),revealed,drawer,const DeepCollectionEquality().hash(drawerWatched),drawerShown,const DeepCollectionEquality().hash(secrets),timelineKey,const DeepCollectionEquality().hash(timelineAudit)]);
}

@override
String toString() {
    return 'AssistantState(draft: $draft, panel: $panel, agent: $agent, config: $config, configInvalid: $configInvalid, docs: $docs, unticked: $unticked, refusals: $refusals, picks: $picks, shown: $shown, watched: $watched, rowPicks: $rowPicks, chips: $chips, revealed: $revealed, drawer: $drawer, drawerWatched: $drawerWatched, drawerShown: $drawerShown, secrets: $secrets, timelineKey: $timelineKey, timelineAudit: $timelineAudit)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 String? draft, AssistantPanel panel, String? agent, AgentConfig? config, bool configInvalid, bool docs, IMap<String, ISet<int>> unticked, IMap<String, String> refusals, IMap<String, ISet<String>> picks, bool shown, IList<String> watched, IMap<String, ISet<String>> rowPicks, IList<String> chips, IMap<String, ISet<int>> revealed, bool drawer, IList<String> drawerWatched, bool drawerShown, ISet<String>? secrets, String? timelineKey, IList<AuditEntry> timelineAudit
});


@override $AgentConfigCopyWith<$Res>? get config;

}
/// @nodoc
class __$AssistantStateCopyWithImpl<$Res>
    implements _$AssistantStateCopyWith<$Res> {
  __$AssistantStateCopyWithImpl(this._self, this._then);

  final _AssistantState _self;
  final $Res Function(_AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draft = freezed,Object? panel = null,Object? agent = freezed,Object? config = freezed,Object? configInvalid = null,Object? docs = null,Object? unticked = null,Object? refusals = null,Object? picks = null,Object? shown = null,Object? watched = null,Object? rowPicks = null,Object? chips = null,Object? revealed = null,Object? drawer = null,Object? drawerWatched = null,Object? drawerShown = null,Object? secrets = freezed,Object? timelineKey = freezed,Object? timelineAudit = null,}) {
  return _then(_AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as AssistantPanel,agent: freezed == agent ? _self.agent : agent // ignore: cast_nullable_to_non_nullable
as String?,config: freezed == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as AgentConfig?,configInvalid: null == configInvalid ? _self.configInvalid : configInvalid // ignore: cast_nullable_to_non_nullable
as bool,docs: null == docs ? _self.docs : docs // ignore: cast_nullable_to_non_nullable
as bool,unticked: null == unticked ? _self.unticked : unticked // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,refusals: null == refusals ? _self.refusals : refusals // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,picks: null == picks ? _self.picks : picks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IList<String>,rowPicks: null == rowPicks ? _self.rowPicks : rowPicks // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<String>>,chips: null == chips ? _self.chips : chips // ignore: cast_nullable_to_non_nullable
as IList<String>,revealed: null == revealed ? _self.revealed : revealed // ignore: cast_nullable_to_non_nullable
as IMap<String, ISet<int>>,drawer: null == drawer ? _self.drawer : drawer // ignore: cast_nullable_to_non_nullable
as bool,drawerWatched: null == drawerWatched ? _self.drawerWatched : drawerWatched // ignore: cast_nullable_to_non_nullable
as IList<String>,drawerShown: null == drawerShown ? _self.drawerShown : drawerShown // ignore: cast_nullable_to_non_nullable
as bool,secrets: freezed == secrets ? _self.secrets : secrets // ignore: cast_nullable_to_non_nullable
as ISet<String>?,timelineKey: freezed == timelineKey ? _self.timelineKey : timelineKey // ignore: cast_nullable_to_non_nullable
as String?,timelineAudit: null == timelineAudit ? _self.timelineAudit : timelineAudit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,
  ));
}

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentConfigCopyWith<$Res>? get config {
    if (_self.config == null) {
    return null;
  }

  return $AgentConfigCopyWith<$Res>(_self.config!, (value) {
    return _then(_self.copyWith(config: value));
  });
}
}

// dart format on
