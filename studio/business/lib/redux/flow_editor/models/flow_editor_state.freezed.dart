// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowEditorState {

 String? get flowId; FlowDraft? get draft; bool get dirty; IList<String> get problems; String? get selectedBlock; IList<NodeType> get types; int get version; String? get state; String? get message; String get palette; IMap<String, LiveValue> get ports; FlowDraft? get deployed; String? get watchRefused;
/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowEditorStateCopyWith<FlowEditorState> get copyWith => _$FlowEditorStateCopyWithImpl<FlowEditorState>(this as FlowEditorState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowEditorState&&(identical(other.flowId, flowId) || other.flowId == flowId)&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.problems, problems)&&(identical(other.selectedBlock, selectedBlock) || other.selectedBlock == selectedBlock)&&const DeepCollectionEquality().equals(other.types, types)&&(identical(other.version, version) || other.version == version)&&(identical(other.state, state) || other.state == state)&&(identical(other.message, message) || other.message == message)&&(identical(other.palette, palette) || other.palette == palette)&&(identical(other.ports, ports) || other.ports == ports)&&(identical(other.deployed, deployed) || other.deployed == deployed)&&(identical(other.watchRefused, watchRefused) || other.watchRefused == watchRefused));
}


@override
int get hashCode => Object.hash(runtimeType,flowId,draft,dirty,const DeepCollectionEquality().hash(problems),selectedBlock,const DeepCollectionEquality().hash(types),version,state,message,palette,ports,deployed,watchRefused);

@override
String toString() {
  return 'FlowEditorState(flowId: $flowId, draft: $draft, dirty: $dirty, problems: $problems, selectedBlock: $selectedBlock, types: $types, version: $version, state: $state, message: $message, palette: $palette, ports: $ports, deployed: $deployed, watchRefused: $watchRefused)';
}


}

/// @nodoc
abstract mixin class $FlowEditorStateCopyWith<$Res>  {
  factory $FlowEditorStateCopyWith(FlowEditorState value, $Res Function(FlowEditorState) _then) = _$FlowEditorStateCopyWithImpl;
@useResult
$Res call({
 String? flowId, FlowDraft? draft, bool dirty, IList<String> problems, String? selectedBlock, IList<NodeType> types, int version, String? state, String? message, String palette, IMap<String, LiveValue> ports, FlowDraft? deployed, String? watchRefused
});


$FlowDraftCopyWith<$Res>? get draft;$FlowDraftCopyWith<$Res>? get deployed;

}
/// @nodoc
class _$FlowEditorStateCopyWithImpl<$Res>
    implements $FlowEditorStateCopyWith<$Res> {
  _$FlowEditorStateCopyWithImpl(this._self, this._then);

  final FlowEditorState _self;
  final $Res Function(FlowEditorState) _then;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? flowId = freezed,Object? draft = freezed,Object? dirty = null,Object? problems = null,Object? selectedBlock = freezed,Object? types = null,Object? version = null,Object? state = freezed,Object? message = freezed,Object? palette = null,Object? ports = null,Object? deployed = freezed,Object? watchRefused = freezed,}) {
  return _then(_self.copyWith(
flowId: freezed == flowId ? _self.flowId : flowId // ignore: cast_nullable_to_non_nullable
as String?,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as FlowDraft?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedBlock: freezed == selectedBlock ? _self.selectedBlock : selectedBlock // ignore: cast_nullable_to_non_nullable
as String?,types: null == types ? _self.types : types // ignore: cast_nullable_to_non_nullable
as IList<NodeType>,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,palette: null == palette ? _self.palette : palette // ignore: cast_nullable_to_non_nullable
as String,ports: null == ports ? _self.ports : ports // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,deployed: freezed == deployed ? _self.deployed : deployed // ignore: cast_nullable_to_non_nullable
as FlowDraft?,watchRefused: freezed == watchRefused ? _self.watchRefused : watchRefused // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $FlowDraftCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res>? get deployed {
    if (_self.deployed == null) {
    return null;
  }

  return $FlowDraftCopyWith<$Res>(_self.deployed!, (value) {
    return _then(_self.copyWith(deployed: value));
  });
}
}



/// @nodoc


class _FlowEditorState implements FlowEditorState {
  const _FlowEditorState({this.flowId, this.draft, this.dirty = false, this.problems = const IListConst([]), this.selectedBlock, this.types = const IListConst([]), this.version = 0, this.state, this.message, this.palette = 'blocks', this.ports = const IMapConst({}), this.deployed, this.watchRefused});
  

@override final  String? flowId;
@override final  FlowDraft? draft;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  IList<String> problems;
@override final  String? selectedBlock;
@override@JsonKey() final  IList<NodeType> types;
@override@JsonKey() final  int version;
@override final  String? state;
@override final  String? message;
@override@JsonKey() final  String palette;
@override@JsonKey() final  IMap<String, LiveValue> ports;
@override final  FlowDraft? deployed;
@override final  String? watchRefused;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowEditorStateCopyWith<_FlowEditorState> get copyWith => __$FlowEditorStateCopyWithImpl<_FlowEditorState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowEditorState&&(identical(other.flowId, flowId) || other.flowId == flowId)&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.problems, problems)&&(identical(other.selectedBlock, selectedBlock) || other.selectedBlock == selectedBlock)&&const DeepCollectionEquality().equals(other.types, types)&&(identical(other.version, version) || other.version == version)&&(identical(other.state, state) || other.state == state)&&(identical(other.message, message) || other.message == message)&&(identical(other.palette, palette) || other.palette == palette)&&(identical(other.ports, ports) || other.ports == ports)&&(identical(other.deployed, deployed) || other.deployed == deployed)&&(identical(other.watchRefused, watchRefused) || other.watchRefused == watchRefused));
}


@override
int get hashCode => Object.hash(runtimeType,flowId,draft,dirty,const DeepCollectionEquality().hash(problems),selectedBlock,const DeepCollectionEquality().hash(types),version,state,message,palette,ports,deployed,watchRefused);

@override
String toString() {
  return 'FlowEditorState(flowId: $flowId, draft: $draft, dirty: $dirty, problems: $problems, selectedBlock: $selectedBlock, types: $types, version: $version, state: $state, message: $message, palette: $palette, ports: $ports, deployed: $deployed, watchRefused: $watchRefused)';
}


}

/// @nodoc
abstract mixin class _$FlowEditorStateCopyWith<$Res> implements $FlowEditorStateCopyWith<$Res> {
  factory _$FlowEditorStateCopyWith(_FlowEditorState value, $Res Function(_FlowEditorState) _then) = __$FlowEditorStateCopyWithImpl;
@override @useResult
$Res call({
 String? flowId, FlowDraft? draft, bool dirty, IList<String> problems, String? selectedBlock, IList<NodeType> types, int version, String? state, String? message, String palette, IMap<String, LiveValue> ports, FlowDraft? deployed, String? watchRefused
});


@override $FlowDraftCopyWith<$Res>? get draft;@override $FlowDraftCopyWith<$Res>? get deployed;

}
/// @nodoc
class __$FlowEditorStateCopyWithImpl<$Res>
    implements _$FlowEditorStateCopyWith<$Res> {
  __$FlowEditorStateCopyWithImpl(this._self, this._then);

  final _FlowEditorState _self;
  final $Res Function(_FlowEditorState) _then;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? flowId = freezed,Object? draft = freezed,Object? dirty = null,Object? problems = null,Object? selectedBlock = freezed,Object? types = null,Object? version = null,Object? state = freezed,Object? message = freezed,Object? palette = null,Object? ports = null,Object? deployed = freezed,Object? watchRefused = freezed,}) {
  return _then(_FlowEditorState(
flowId: freezed == flowId ? _self.flowId : flowId // ignore: cast_nullable_to_non_nullable
as String?,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as FlowDraft?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedBlock: freezed == selectedBlock ? _self.selectedBlock : selectedBlock // ignore: cast_nullable_to_non_nullable
as String?,types: null == types ? _self.types : types // ignore: cast_nullable_to_non_nullable
as IList<NodeType>,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,palette: null == palette ? _self.palette : palette // ignore: cast_nullable_to_non_nullable
as String,ports: null == ports ? _self.ports : ports // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,deployed: freezed == deployed ? _self.deployed : deployed // ignore: cast_nullable_to_non_nullable
as FlowDraft?,watchRefused: freezed == watchRefused ? _self.watchRefused : watchRefused // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $FlowDraftCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res>? get deployed {
    if (_self.deployed == null) {
    return null;
  }

  return $FlowDraftCopyWith<$Res>(_self.deployed!, (value) {
    return _then(_self.copyWith(deployed: value));
  });
}
}

// dart format on
