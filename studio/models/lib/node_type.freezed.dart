// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'node_type.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NodeType {

 String get type; String get category; String get description; IList<String> get inputs; IList<String> get outputs;/// Ports a parameter adds: `(param, prefix, defaults)`.
 String? get dynInParam; String get dynInPrefix; IList<String> get dynInDefaults; String? get dynOutParam; String get dynOutPrefix; IList<String> get dynOutDefaults; IList<ParamSpec> get params;
/// Create a copy of NodeType
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodeTypeCopyWith<NodeType> get copyWith => _$NodeTypeCopyWithImpl<NodeType>(this as NodeType, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodeType&&(identical(other.type, type) || other.type == type)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.inputs, inputs)&&const DeepCollectionEquality().equals(other.outputs, outputs)&&(identical(other.dynInParam, dynInParam) || other.dynInParam == dynInParam)&&(identical(other.dynInPrefix, dynInPrefix) || other.dynInPrefix == dynInPrefix)&&const DeepCollectionEquality().equals(other.dynInDefaults, dynInDefaults)&&(identical(other.dynOutParam, dynOutParam) || other.dynOutParam == dynOutParam)&&(identical(other.dynOutPrefix, dynOutPrefix) || other.dynOutPrefix == dynOutPrefix)&&const DeepCollectionEquality().equals(other.dynOutDefaults, dynOutDefaults)&&const DeepCollectionEquality().equals(other.params, params));
}


@override
int get hashCode => Object.hash(runtimeType,type,category,description,const DeepCollectionEquality().hash(inputs),const DeepCollectionEquality().hash(outputs),dynInParam,dynInPrefix,const DeepCollectionEquality().hash(dynInDefaults),dynOutParam,dynOutPrefix,const DeepCollectionEquality().hash(dynOutDefaults),const DeepCollectionEquality().hash(params));

@override
String toString() {
  return 'NodeType(type: $type, category: $category, description: $description, inputs: $inputs, outputs: $outputs, dynInParam: $dynInParam, dynInPrefix: $dynInPrefix, dynInDefaults: $dynInDefaults, dynOutParam: $dynOutParam, dynOutPrefix: $dynOutPrefix, dynOutDefaults: $dynOutDefaults, params: $params)';
}


}

/// @nodoc
abstract mixin class $NodeTypeCopyWith<$Res>  {
  factory $NodeTypeCopyWith(NodeType value, $Res Function(NodeType) _then) = _$NodeTypeCopyWithImpl;
@useResult
$Res call({
 String type, String category, String description, IList<String> inputs, IList<String> outputs, String? dynInParam, String dynInPrefix, IList<String> dynInDefaults, String? dynOutParam, String dynOutPrefix, IList<String> dynOutDefaults, IList<ParamSpec> params
});




}
/// @nodoc
class _$NodeTypeCopyWithImpl<$Res>
    implements $NodeTypeCopyWith<$Res> {
  _$NodeTypeCopyWithImpl(this._self, this._then);

  final NodeType _self;
  final $Res Function(NodeType) _then;

/// Create a copy of NodeType
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? category = null,Object? description = null,Object? inputs = null,Object? outputs = null,Object? dynInParam = freezed,Object? dynInPrefix = null,Object? dynInDefaults = null,Object? dynOutParam = freezed,Object? dynOutPrefix = null,Object? dynOutDefaults = null,Object? params = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,inputs: null == inputs ? _self.inputs : inputs // ignore: cast_nullable_to_non_nullable
as IList<String>,outputs: null == outputs ? _self.outputs : outputs // ignore: cast_nullable_to_non_nullable
as IList<String>,dynInParam: freezed == dynInParam ? _self.dynInParam : dynInParam // ignore: cast_nullable_to_non_nullable
as String?,dynInPrefix: null == dynInPrefix ? _self.dynInPrefix : dynInPrefix // ignore: cast_nullable_to_non_nullable
as String,dynInDefaults: null == dynInDefaults ? _self.dynInDefaults : dynInDefaults // ignore: cast_nullable_to_non_nullable
as IList<String>,dynOutParam: freezed == dynOutParam ? _self.dynOutParam : dynOutParam // ignore: cast_nullable_to_non_nullable
as String?,dynOutPrefix: null == dynOutPrefix ? _self.dynOutPrefix : dynOutPrefix // ignore: cast_nullable_to_non_nullable
as String,dynOutDefaults: null == dynOutDefaults ? _self.dynOutDefaults : dynOutDefaults // ignore: cast_nullable_to_non_nullable
as IList<String>,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IList<ParamSpec>,
  ));
}

}



/// @nodoc


class _NodeType implements NodeType {
  const _NodeType({required this.type, this.category = '', this.description = '', this.inputs = const IListConst([]), this.outputs = const IListConst([]), this.dynInParam, this.dynInPrefix = '', this.dynInDefaults = const IListConst([]), this.dynOutParam, this.dynOutPrefix = '', this.dynOutDefaults = const IListConst([]), this.params = const IListConst([])});
  

@override final  String type;
@override@JsonKey() final  String category;
@override@JsonKey() final  String description;
@override@JsonKey() final  IList<String> inputs;
@override@JsonKey() final  IList<String> outputs;
/// Ports a parameter adds: `(param, prefix, defaults)`.
@override final  String? dynInParam;
@override@JsonKey() final  String dynInPrefix;
@override@JsonKey() final  IList<String> dynInDefaults;
@override final  String? dynOutParam;
@override@JsonKey() final  String dynOutPrefix;
@override@JsonKey() final  IList<String> dynOutDefaults;
@override@JsonKey() final  IList<ParamSpec> params;

/// Create a copy of NodeType
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodeTypeCopyWith<_NodeType> get copyWith => __$NodeTypeCopyWithImpl<_NodeType>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodeType&&(identical(other.type, type) || other.type == type)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.inputs, inputs)&&const DeepCollectionEquality().equals(other.outputs, outputs)&&(identical(other.dynInParam, dynInParam) || other.dynInParam == dynInParam)&&(identical(other.dynInPrefix, dynInPrefix) || other.dynInPrefix == dynInPrefix)&&const DeepCollectionEquality().equals(other.dynInDefaults, dynInDefaults)&&(identical(other.dynOutParam, dynOutParam) || other.dynOutParam == dynOutParam)&&(identical(other.dynOutPrefix, dynOutPrefix) || other.dynOutPrefix == dynOutPrefix)&&const DeepCollectionEquality().equals(other.dynOutDefaults, dynOutDefaults)&&const DeepCollectionEquality().equals(other.params, params));
}


@override
int get hashCode => Object.hash(runtimeType,type,category,description,const DeepCollectionEquality().hash(inputs),const DeepCollectionEquality().hash(outputs),dynInParam,dynInPrefix,const DeepCollectionEquality().hash(dynInDefaults),dynOutParam,dynOutPrefix,const DeepCollectionEquality().hash(dynOutDefaults),const DeepCollectionEquality().hash(params));

@override
String toString() {
  return 'NodeType(type: $type, category: $category, description: $description, inputs: $inputs, outputs: $outputs, dynInParam: $dynInParam, dynInPrefix: $dynInPrefix, dynInDefaults: $dynInDefaults, dynOutParam: $dynOutParam, dynOutPrefix: $dynOutPrefix, dynOutDefaults: $dynOutDefaults, params: $params)';
}


}

/// @nodoc
abstract mixin class _$NodeTypeCopyWith<$Res> implements $NodeTypeCopyWith<$Res> {
  factory _$NodeTypeCopyWith(_NodeType value, $Res Function(_NodeType) _then) = __$NodeTypeCopyWithImpl;
@override @useResult
$Res call({
 String type, String category, String description, IList<String> inputs, IList<String> outputs, String? dynInParam, String dynInPrefix, IList<String> dynInDefaults, String? dynOutParam, String dynOutPrefix, IList<String> dynOutDefaults, IList<ParamSpec> params
});




}
/// @nodoc
class __$NodeTypeCopyWithImpl<$Res>
    implements _$NodeTypeCopyWith<$Res> {
  __$NodeTypeCopyWithImpl(this._self, this._then);

  final _NodeType _self;
  final $Res Function(_NodeType) _then;

/// Create a copy of NodeType
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? category = null,Object? description = null,Object? inputs = null,Object? outputs = null,Object? dynInParam = freezed,Object? dynInPrefix = null,Object? dynInDefaults = null,Object? dynOutParam = freezed,Object? dynOutPrefix = null,Object? dynOutDefaults = null,Object? params = null,}) {
  return _then(_NodeType(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,inputs: null == inputs ? _self.inputs : inputs // ignore: cast_nullable_to_non_nullable
as IList<String>,outputs: null == outputs ? _self.outputs : outputs // ignore: cast_nullable_to_non_nullable
as IList<String>,dynInParam: freezed == dynInParam ? _self.dynInParam : dynInParam // ignore: cast_nullable_to_non_nullable
as String?,dynInPrefix: null == dynInPrefix ? _self.dynInPrefix : dynInPrefix // ignore: cast_nullable_to_non_nullable
as String,dynInDefaults: null == dynInDefaults ? _self.dynInDefaults : dynInDefaults // ignore: cast_nullable_to_non_nullable
as IList<String>,dynOutParam: freezed == dynOutParam ? _self.dynOutParam : dynOutParam // ignore: cast_nullable_to_non_nullable
as String?,dynOutPrefix: null == dynOutPrefix ? _self.dynOutPrefix : dynOutPrefix // ignore: cast_nullable_to_non_nullable
as String,dynOutDefaults: null == dynOutDefaults ? _self.dynOutDefaults : dynOutDefaults // ignore: cast_nullable_to_non_nullable
as IList<String>,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IList<ParamSpec>,
  ));
}


}

// dart format on
