// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowDraft {

 String get id; int get version; IMap<String, FlowBlock> get blocks; IList<FlowEdge> get edges; IMap<String, Object?> get rest;/// The custom blocks of the definition (`blocks`), decoded, by name.
 IMap<String, BlockDef> get defs;/// `description`, decoded (it is in [rest] too, as it came, for the
/// write back); null when the definition has no text there.
 String? get description;/// `permissions`, decoded (it is in [rest] too, as it came, for the
/// write back); null when the definition has none.
 FlowPermissions? get permissions;
/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<FlowDraft> get copyWith => _$FlowDraftCopyWithImpl<FlowDraft>(this as FlowDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FlowDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowDraft&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.blocks, _this.blocks) || other.blocks == _this.blocks)&&const DeepCollectionEquality().equals(other.edges, _this.edges)&&(identical(other.rest, _this.rest) || other.rest == _this.rest)&&(identical(other.defs, _this.defs) || other.defs == _this.defs)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.permissions, _this.permissions) || other.permissions == _this.permissions));
}


@override
int get hashCode {
  final _this = this as FlowDraft;
  return Object.hash(runtimeType,_this.id,_this.version,_this.blocks,const DeepCollectionEquality().hash(_this.edges),_this.rest,_this.defs,_this.description,_this.permissions);
}

@override
String toString() {
  final _this = this as FlowDraft;
  return 'FlowDraft(id: ${_this.id}, version: ${_this.version}, blocks: ${_this.blocks}, edges: ${_this.edges}, rest: ${_this.rest}, defs: ${_this.defs}, description: ${_this.description}, permissions: ${_this.permissions})';
}


}

/// @nodoc
abstract mixin class $FlowDraftCopyWith<$Res>  {
  factory $FlowDraftCopyWith(FlowDraft value, $Res Function(FlowDraft) _then) = _$FlowDraftCopyWithImpl;
@useResult
$Res call({
 String id, int version, IMap<String, FlowBlock> blocks, IList<FlowEdge> edges, IMap<String, Object?> rest, IMap<String, BlockDef> defs, String? description, FlowPermissions? permissions
});


$FlowPermissionsCopyWith<$Res>? get permissions;

}
/// @nodoc
class _$FlowDraftCopyWithImpl<$Res>
    implements $FlowDraftCopyWith<$Res> {
  _$FlowDraftCopyWithImpl(this._self, this._then);

  final FlowDraft _self;
  final $Res Function(FlowDraft) _then;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? version = null,Object? blocks = null,Object? edges = null,Object? rest = null,Object? defs = null,Object? description = freezed,Object? permissions = freezed,}) {
  return _then(FlowDraft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowBlock>,edges: null == edges ? _self.edges : edges // ignore: cast_nullable_to_non_nullable
as IList<FlowEdge>,rest: null == rest ? _self.rest : rest // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,defs: null == defs ? _self.defs : defs // ignore: cast_nullable_to_non_nullable
as IMap<String, BlockDef>,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,permissions: freezed == permissions ? _self.permissions : permissions // ignore: cast_nullable_to_non_nullable
as FlowPermissions?,
  ));
}
/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowPermissionsCopyWith<$Res>? get permissions {
    if (_self.permissions == null) {
    return null;
  }

  return $FlowPermissionsCopyWith<$Res>(_self.permissions!, (value) {
    return _then(_self.copyWith(permissions: value));
  });
}
}



/// @nodoc


class _FlowDraft implements FlowDraft {
  const _FlowDraft({required this.id, this.version = 0, this.blocks = const IMapConst({}), this.edges = const IListConst([]), this.rest = const IMapConst({}), this.defs = const IMapConst({}), this.description, this.permissions});
  

@override final  String id;
@override@JsonKey() final  int version;
@override@JsonKey() final  IMap<String, FlowBlock> blocks;
@override@JsonKey() final  IList<FlowEdge> edges;
@override@JsonKey() final  IMap<String, Object?> rest;
/// The custom blocks of the definition (`blocks`), decoded, by name.
@override@JsonKey() final  IMap<String, BlockDef> defs;
/// `description`, decoded (it is in [rest] too, as it came, for the
/// write back); null when the definition has no text there.
@override final  String? description;
/// `permissions`, decoded (it is in [rest] too, as it came, for the
/// write back); null when the definition has none.
@override final  FlowPermissions? permissions;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowDraftCopyWith<_FlowDraft> get copyWith => __$FlowDraftCopyWithImpl<_FlowDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.version, version) || other.version == version)&&(identical(other.blocks, blocks) || other.blocks == blocks)&&const DeepCollectionEquality().equals(other.edges, edges)&&(identical(other.rest, rest) || other.rest == rest)&&(identical(other.defs, defs) || other.defs == defs)&&(identical(other.description, description) || other.description == description)&&(identical(other.permissions, permissions) || other.permissions == permissions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,version,blocks,const DeepCollectionEquality().hash(edges),rest,defs,description,permissions);
}

@override
String toString() {
    return 'FlowDraft(id: $id, version: $version, blocks: $blocks, edges: $edges, rest: $rest, defs: $defs, description: $description, permissions: $permissions)';
}


}

/// @nodoc
abstract mixin class _$FlowDraftCopyWith<$Res> implements $FlowDraftCopyWith<$Res> {
  factory _$FlowDraftCopyWith(_FlowDraft value, $Res Function(_FlowDraft) _then) = __$FlowDraftCopyWithImpl;
@override @useResult
$Res call({
 String id, int version, IMap<String, FlowBlock> blocks, IList<FlowEdge> edges, IMap<String, Object?> rest, IMap<String, BlockDef> defs, String? description, FlowPermissions? permissions
});


@override $FlowPermissionsCopyWith<$Res>? get permissions;

}
/// @nodoc
class __$FlowDraftCopyWithImpl<$Res>
    implements _$FlowDraftCopyWith<$Res> {
  __$FlowDraftCopyWithImpl(this._self, this._then);

  final _FlowDraft _self;
  final $Res Function(_FlowDraft) _then;

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? version = null,Object? blocks = null,Object? edges = null,Object? rest = null,Object? defs = null,Object? description = freezed,Object? permissions = freezed,}) {
  return _then(_FlowDraft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowBlock>,edges: null == edges ? _self.edges : edges // ignore: cast_nullable_to_non_nullable
as IList<FlowEdge>,rest: null == rest ? _self.rest : rest // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,defs: null == defs ? _self.defs : defs // ignore: cast_nullable_to_non_nullable
as IMap<String, BlockDef>,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,permissions: freezed == permissions ? _self.permissions : permissions // ignore: cast_nullable_to_non_nullable
as FlowPermissions?,
  ));
}

/// Create a copy of FlowDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowPermissionsCopyWith<$Res>? get permissions {
    if (_self.permissions == null) {
    return null;
  }

  return $FlowPermissionsCopyWith<$Res>(_self.permissions!, (value) {
    return _then(_self.copyWith(permissions: value));
  });
}
}

// dart format on
