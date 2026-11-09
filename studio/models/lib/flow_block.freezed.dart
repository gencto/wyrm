// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_block.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowBlock {

 String get id; String get type;/// The node's config without `type`, as JSON values.
 IMap<String, Object?> get cfg; double get x; double get y;/// The fields the user pinned to the block or took off it, by field id
/// (`p:input_min` → true: a row of the block; false: only in the
/// inspector). A field without an entry follows its type's default.
/// Editor data, kept in the definition's `layout`.
 IMap<String, bool> get pins;
/// Create a copy of FlowBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowBlockCopyWith<FlowBlock> get copyWith => _$FlowBlockCopyWithImpl<FlowBlock>(this as FlowBlock, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowBlock&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.pins, pins) || other.pins == pins));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,cfg,x,y,pins);

@override
String toString() {
  return 'FlowBlock(id: $id, type: $type, cfg: $cfg, x: $x, y: $y, pins: $pins)';
}


}

/// @nodoc
abstract mixin class $FlowBlockCopyWith<$Res>  {
  factory $FlowBlockCopyWith(FlowBlock value, $Res Function(FlowBlock) _then) = _$FlowBlockCopyWithImpl;
@useResult
$Res call({
 String id, String type, IMap<String, Object?> cfg, double x, double y, IMap<String, bool> pins
});




}
/// @nodoc
class _$FlowBlockCopyWithImpl<$Res>
    implements $FlowBlockCopyWith<$Res> {
  _$FlowBlockCopyWithImpl(this._self, this._then);

  final FlowBlock _self;
  final $Res Function(FlowBlock) _then;

/// Create a copy of FlowBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? cfg = null,Object? x = null,Object? y = null,Object? pins = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,pins: null == pins ? _self.pins : pins // ignore: cast_nullable_to_non_nullable
as IMap<String, bool>,
  ));
}

}



/// @nodoc


class _FlowBlock implements FlowBlock {
  const _FlowBlock({required this.id, required this.type, this.cfg = const IMapConst({}), this.x = 0, this.y = 0, this.pins = const IMapConst({})});
  

@override final  String id;
@override final  String type;
/// The node's config without `type`, as JSON values.
@override@JsonKey() final  IMap<String, Object?> cfg;
@override@JsonKey() final  double x;
@override@JsonKey() final  double y;
/// The fields the user pinned to the block or took off it, by field id
/// (`p:input_min` → true: a row of the block; false: only in the
/// inspector). A field without an entry follows its type's default.
/// Editor data, kept in the definition's `layout`.
@override@JsonKey() final  IMap<String, bool> pins;

/// Create a copy of FlowBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowBlockCopyWith<_FlowBlock> get copyWith => __$FlowBlockCopyWithImpl<_FlowBlock>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowBlock&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.cfg, cfg) || other.cfg == cfg)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.pins, pins) || other.pins == pins));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,cfg,x,y,pins);

@override
String toString() {
  return 'FlowBlock(id: $id, type: $type, cfg: $cfg, x: $x, y: $y, pins: $pins)';
}


}

/// @nodoc
abstract mixin class _$FlowBlockCopyWith<$Res> implements $FlowBlockCopyWith<$Res> {
  factory _$FlowBlockCopyWith(_FlowBlock value, $Res Function(_FlowBlock) _then) = __$FlowBlockCopyWithImpl;
@override @useResult
$Res call({
 String id, String type, IMap<String, Object?> cfg, double x, double y, IMap<String, bool> pins
});




}
/// @nodoc
class __$FlowBlockCopyWithImpl<$Res>
    implements _$FlowBlockCopyWith<$Res> {
  __$FlowBlockCopyWithImpl(this._self, this._then);

  final _FlowBlock _self;
  final $Res Function(_FlowBlock) _then;

/// Create a copy of FlowBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? cfg = null,Object? x = null,Object? y = null,Object? pins = null,}) {
  return _then(_FlowBlock(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,cfg: null == cfg ? _self.cfg : cfg // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,pins: null == pins ? _self.pins : pins // ignore: cast_nullable_to_non_nullable
as IMap<String, bool>,
  ));
}


}

// dart format on
