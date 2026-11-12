// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowSummary {

 String get id; int? get version; String? get deployedBy; bool get draft; String? get problem; IList<String> get reads; IList<String> get writes; int get blocks; String? get description; bool get running;
/// Create a copy of FlowSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowSummaryCopyWith<FlowSummary> get copyWith => _$FlowSummaryCopyWithImpl<FlowSummary>(this as FlowSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FlowSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowSummary&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.deployedBy, _this.deployedBy) || other.deployedBy == _this.deployedBy)&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.problem, _this.problem) || other.problem == _this.problem)&&const DeepCollectionEquality().equals(other.reads, _this.reads)&&const DeepCollectionEquality().equals(other.writes, _this.writes)&&(identical(other.blocks, _this.blocks) || other.blocks == _this.blocks)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.running, _this.running) || other.running == _this.running));
}


@override
int get hashCode {
  final _this = this as FlowSummary;
  return Object.hash(runtimeType,_this.id,_this.version,_this.deployedBy,_this.draft,_this.problem,const DeepCollectionEquality().hash(_this.reads),const DeepCollectionEquality().hash(_this.writes),_this.blocks,_this.description,_this.running);
}

@override
String toString() {
  final _this = this as FlowSummary;
  return 'FlowSummary(id: ${_this.id}, version: ${_this.version}, deployedBy: ${_this.deployedBy}, draft: ${_this.draft}, problem: ${_this.problem}, reads: ${_this.reads}, writes: ${_this.writes}, blocks: ${_this.blocks}, description: ${_this.description}, running: ${_this.running})';
}


}

/// @nodoc
abstract mixin class $FlowSummaryCopyWith<$Res>  {
  factory $FlowSummaryCopyWith(FlowSummary value, $Res Function(FlowSummary) _then) = _$FlowSummaryCopyWithImpl;
@useResult
$Res call({
 String id, int? version, String? deployedBy, bool draft, String? problem, IList<String> reads, IList<String> writes, int blocks, String? description, bool running
});




}
/// @nodoc
class _$FlowSummaryCopyWithImpl<$Res>
    implements $FlowSummaryCopyWith<$Res> {
  _$FlowSummaryCopyWithImpl(this._self, this._then);

  final FlowSummary _self;
  final $Res Function(FlowSummary) _then;

/// Create a copy of FlowSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? version = freezed,Object? deployedBy = freezed,Object? draft = null,Object? problem = freezed,Object? reads = null,Object? writes = null,Object? blocks = null,Object? description = freezed,Object? running = null,}) {
  return _then(FlowSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int?,deployedBy: freezed == deployedBy ? _self.deployedBy : deployedBy // ignore: cast_nullable_to_non_nullable
as String?,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as bool,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as String?,reads: null == reads ? _self.reads : reads // ignore: cast_nullable_to_non_nullable
as IList<String>,writes: null == writes ? _self.writes : writes // ignore: cast_nullable_to_non_nullable
as IList<String>,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _FlowSummary implements FlowSummary {
  const _FlowSummary({required this.id, this.version, this.deployedBy, this.draft = false, this.problem, this.reads = const IListConst([]), this.writes = const IListConst([]), this.blocks = 0, this.description, this.running = false});
  

@override final  String id;
@override final  int? version;
@override final  String? deployedBy;
@override@JsonKey() final  bool draft;
@override final  String? problem;
@override@JsonKey() final  IList<String> reads;
@override@JsonKey() final  IList<String> writes;
@override@JsonKey() final  int blocks;
@override final  String? description;
@override@JsonKey() final  bool running;

/// Create a copy of FlowSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowSummaryCopyWith<_FlowSummary> get copyWith => __$FlowSummaryCopyWithImpl<_FlowSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.version, version) || other.version == version)&&(identical(other.deployedBy, deployedBy) || other.deployedBy == deployedBy)&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.problem, problem) || other.problem == problem)&&const DeepCollectionEquality().equals(other.reads, reads)&&const DeepCollectionEquality().equals(other.writes, writes)&&(identical(other.blocks, blocks) || other.blocks == blocks)&&(identical(other.description, description) || other.description == description)&&(identical(other.running, running) || other.running == running));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,version,deployedBy,draft,problem,const DeepCollectionEquality().hash(reads),const DeepCollectionEquality().hash(writes),blocks,description,running);
}

@override
String toString() {
    return 'FlowSummary(id: $id, version: $version, deployedBy: $deployedBy, draft: $draft, problem: $problem, reads: $reads, writes: $writes, blocks: $blocks, description: $description, running: $running)';
}


}

/// @nodoc
abstract mixin class _$FlowSummaryCopyWith<$Res> implements $FlowSummaryCopyWith<$Res> {
  factory _$FlowSummaryCopyWith(_FlowSummary value, $Res Function(_FlowSummary) _then) = __$FlowSummaryCopyWithImpl;
@override @useResult
$Res call({
 String id, int? version, String? deployedBy, bool draft, String? problem, IList<String> reads, IList<String> writes, int blocks, String? description, bool running
});




}
/// @nodoc
class __$FlowSummaryCopyWithImpl<$Res>
    implements _$FlowSummaryCopyWith<$Res> {
  __$FlowSummaryCopyWithImpl(this._self, this._then);

  final _FlowSummary _self;
  final $Res Function(_FlowSummary) _then;

/// Create a copy of FlowSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? version = freezed,Object? deployedBy = freezed,Object? draft = null,Object? problem = freezed,Object? reads = null,Object? writes = null,Object? blocks = null,Object? description = freezed,Object? running = null,}) {
  return _then(_FlowSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int?,deployedBy: freezed == deployedBy ? _self.deployedBy : deployedBy // ignore: cast_nullable_to_non_nullable
as String?,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as bool,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as String?,reads: null == reads ? _self.reads : reads // ignore: cast_nullable_to_non_nullable
as IList<String>,writes: null == writes ? _self.writes : writes // ignore: cast_nullable_to_non_nullable
as IList<String>,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
