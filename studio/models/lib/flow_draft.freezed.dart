// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowDraft {

 String get id; int get version; IMap<String, FlowBlock> get blocks; IList<FlowEdge> get edges; IMap<String, Object?> get rest;
/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<FlowDraft> get copyWith => _$FlowDraftCopyWithImpl<FlowDraft>(this as FlowDraft, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.version, version) || other.version == version)&&(identical(other.blocks, blocks) || other.blocks == blocks)&&const DeepCollectionEquality().equals(other.edges, edges)&&(identical(other.rest, rest) || other.rest == rest));
}


@override
int get hashCode => Object.hash(runtimeType,id,version,blocks,const DeepCollectionEquality().hash(edges),rest);

@override
String toString() {
  return 'FlowDraft(id: $id, version: $version, blocks: $blocks, edges: $edges, rest: $rest)';
}


}

/// @nodoc
abstract mixin class $FlowDraftCopyWith<$Res>  {
  factory $FlowDraftCopyWith(FlowDraft value, $Res Function(FlowDraft) _then) = _$FlowDraftCopyWithImpl;
@useResult
$Res call({
 String id, int version, IMap<String, FlowBlock> blocks, IList<FlowEdge> edges, IMap<String, Object?> rest
});




}
/// @nodoc
class _$FlowDraftCopyWithImpl<$Res>
    implements $FlowDraftCopyWith<$Res> {
  _$FlowDraftCopyWithImpl(this._self, this._then);

  final FlowDraft _self;
  final $Res Function(FlowDraft) _then;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? version = null,Object? blocks = null,Object? edges = null,Object? rest = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowBlock>,edges: null == edges ? _self.edges : edges // ignore: cast_nullable_to_non_nullable
as IList<FlowEdge>,rest: null == rest ? _self.rest : rest // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}

}



/// @nodoc


class _FlowDraft implements FlowDraft {
  const _FlowDraft({required this.id, this.version = 0, this.blocks = const IMapConst({}), this.edges = const IListConst([]), this.rest = const IMapConst({})});
  

@override final  String id;
@override@JsonKey() final  int version;
@override@JsonKey() final  IMap<String, FlowBlock> blocks;
@override@JsonKey() final  IList<FlowEdge> edges;
@override@JsonKey() final  IMap<String, Object?> rest;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowDraftCopyWith<_FlowDraft> get copyWith => __$FlowDraftCopyWithImpl<_FlowDraft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.version, version) || other.version == version)&&(identical(other.blocks, blocks) || other.blocks == blocks)&&const DeepCollectionEquality().equals(other.edges, edges)&&(identical(other.rest, rest) || other.rest == rest));
}


@override
int get hashCode => Object.hash(runtimeType,id,version,blocks,const DeepCollectionEquality().hash(edges),rest);

@override
String toString() {
  return 'FlowDraft(id: $id, version: $version, blocks: $blocks, edges: $edges, rest: $rest)';
}


}

/// @nodoc
abstract mixin class _$FlowDraftCopyWith<$Res> implements $FlowDraftCopyWith<$Res> {
  factory _$FlowDraftCopyWith(_FlowDraft value, $Res Function(_FlowDraft) _then) = __$FlowDraftCopyWithImpl;
@override @useResult
$Res call({
 String id, int version, IMap<String, FlowBlock> blocks, IList<FlowEdge> edges, IMap<String, Object?> rest
});




}
/// @nodoc
class __$FlowDraftCopyWithImpl<$Res>
    implements _$FlowDraftCopyWith<$Res> {
  __$FlowDraftCopyWithImpl(this._self, this._then);

  final _FlowDraft _self;
  final $Res Function(_FlowDraft) _then;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? version = null,Object? blocks = null,Object? edges = null,Object? rest = null,}) {
  return _then(_FlowDraft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowBlock>,edges: null == edges ? _self.edges : edges // ignore: cast_nullable_to_non_nullable
as IList<FlowEdge>,rest: null == rest ? _self.rest : rest // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}


}

// dart format on
