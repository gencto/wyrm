// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'block_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlockInfo {

 String get name;/// Each `put_block` is the next version.
 int get version; String? get description; IList<String> get inputs; IList<String> get outputs;
/// Create a copy of BlockInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockInfoCopyWith<BlockInfo> get copyWith => _$BlockInfoCopyWithImpl<BlockInfo>(this as BlockInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlockInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.inputs, _this.inputs)&&const DeepCollectionEquality().equals(other.outputs, _this.outputs));
}


@override
int get hashCode {
  final _this = this as BlockInfo;
  return Object.hash(runtimeType,_this.name,_this.version,_this.description,const DeepCollectionEquality().hash(_this.inputs),const DeepCollectionEquality().hash(_this.outputs));
}

@override
String toString() {
  final _this = this as BlockInfo;
  return 'BlockInfo(name: ${_this.name}, version: ${_this.version}, description: ${_this.description}, inputs: ${_this.inputs}, outputs: ${_this.outputs})';
}


}

/// @nodoc
abstract mixin class $BlockInfoCopyWith<$Res>  {
  factory $BlockInfoCopyWith(BlockInfo value, $Res Function(BlockInfo) _then) = _$BlockInfoCopyWithImpl;
@useResult
$Res call({
 String name, int version, String? description, IList<String> inputs, IList<String> outputs
});




}
/// @nodoc
class _$BlockInfoCopyWithImpl<$Res>
    implements $BlockInfoCopyWith<$Res> {
  _$BlockInfoCopyWithImpl(this._self, this._then);

  final BlockInfo _self;
  final $Res Function(BlockInfo) _then;

/// Create a copy of BlockInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? version = null,Object? description = freezed,Object? inputs = null,Object? outputs = null,}) {
  return _then(BlockInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,inputs: null == inputs ? _self.inputs : inputs // ignore: cast_nullable_to_non_nullable
as IList<String>,outputs: null == outputs ? _self.outputs : outputs // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _BlockInfo implements BlockInfo {
  const _BlockInfo({required this.name, this.version = 0, this.description, this.inputs = const IListConst([]), this.outputs = const IListConst([])});
  

@override final  String name;
/// Each `put_block` is the next version.
@override@JsonKey() final  int version;
@override final  String? description;
@override@JsonKey() final  IList<String> inputs;
@override@JsonKey() final  IList<String> outputs;

/// Create a copy of BlockInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlockInfoCopyWith<_BlockInfo> get copyWith => __$BlockInfoCopyWithImpl<_BlockInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlockInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.inputs, inputs)&&const DeepCollectionEquality().equals(other.outputs, outputs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,version,description,const DeepCollectionEquality().hash(inputs),const DeepCollectionEquality().hash(outputs));
}

@override
String toString() {
    return 'BlockInfo(name: $name, version: $version, description: $description, inputs: $inputs, outputs: $outputs)';
}


}

/// @nodoc
abstract mixin class _$BlockInfoCopyWith<$Res> implements $BlockInfoCopyWith<$Res> {
  factory _$BlockInfoCopyWith(_BlockInfo value, $Res Function(_BlockInfo) _then) = __$BlockInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, int version, String? description, IList<String> inputs, IList<String> outputs
});




}
/// @nodoc
class __$BlockInfoCopyWithImpl<$Res>
    implements _$BlockInfoCopyWith<$Res> {
  __$BlockInfoCopyWithImpl(this._self, this._then);

  final _BlockInfo _self;
  final $Res Function(_BlockInfo) _then;

/// Create a copy of BlockInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = null,Object? description = freezed,Object? inputs = null,Object? outputs = null,}) {
  return _then(_BlockInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,inputs: null == inputs ? _self.inputs : inputs // ignore: cast_nullable_to_non_nullable
as IList<String>,outputs: null == outputs ? _self.outputs : outputs // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
