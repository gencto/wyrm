// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'param_spec.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParamSpec {

 String get name; String? get display;/// TypeCode name (`string`, `number`, `int`, `bool`, `enum`, …).
 String get type; bool get required; Object? get defaultValue; num? get min; num? get max; IList<String> get choices;/// `file`, `textarea`, …
 String? get editor; bool get secret; String? get description;/// The input port that feeds it (`in.<name>`, ADR 0038 §2); null when
/// the catalog does not say or it has none.
 String? get port;/// Whether it repeats as an output named like it (ADR 0038 §1); null
/// when the catalog does not say.
 bool? get echo;/// The parameter that holds this field's scope (catalog
/// `params[].scope`, ADR 0040 §1: `key` → `key_scope`): a key from the
/// field's port is read only inside it.
 String? get scope;
/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParamSpecCopyWith<ParamSpec> get copyWith => _$ParamSpecCopyWithImpl<ParamSpec>(this as ParamSpec, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ParamSpec;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParamSpec&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.display, _this.display) || other.display == _this.display)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.required, _this.required) || other.required == _this.required)&&const DeepCollectionEquality().equals(other.defaultValue, _this.defaultValue)&&(identical(other.min, _this.min) || other.min == _this.min)&&(identical(other.max, _this.max) || other.max == _this.max)&&const DeepCollectionEquality().equals(other.choices, _this.choices)&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.secret, _this.secret) || other.secret == _this.secret)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.port, _this.port) || other.port == _this.port)&&(identical(other.echo, _this.echo) || other.echo == _this.echo)&&(identical(other.scope, _this.scope) || other.scope == _this.scope));
}


@override
int get hashCode {
  final _this = this as ParamSpec;
  return Object.hash(runtimeType,_this.name,_this.display,_this.type,_this.required,const DeepCollectionEquality().hash(_this.defaultValue),_this.min,_this.max,const DeepCollectionEquality().hash(_this.choices),_this.editor,_this.secret,_this.description,_this.port,_this.echo,_this.scope);
}

@override
String toString() {
  final _this = this as ParamSpec;
  return 'ParamSpec(name: ${_this.name}, display: ${_this.display}, type: ${_this.type}, required: ${_this.required}, defaultValue: ${_this.defaultValue}, min: ${_this.min}, max: ${_this.max}, choices: ${_this.choices}, editor: ${_this.editor}, secret: ${_this.secret}, description: ${_this.description}, port: ${_this.port}, echo: ${_this.echo}, scope: ${_this.scope})';
}


}

/// @nodoc
abstract mixin class $ParamSpecCopyWith<$Res>  {
  factory $ParamSpecCopyWith(ParamSpec value, $Res Function(ParamSpec) _then) = _$ParamSpecCopyWithImpl;
@useResult
$Res call({
 String name, String? display, String type, bool required, Object? defaultValue, num? min, num? max, IList<String> choices, String? editor, bool secret, String? description, String? port, bool? echo, String? scope
});




}
/// @nodoc
class _$ParamSpecCopyWithImpl<$Res>
    implements $ParamSpecCopyWith<$Res> {
  _$ParamSpecCopyWithImpl(this._self, this._then);

  final ParamSpec _self;
  final $Res Function(ParamSpec) _then;

/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? display = freezed,Object? type = null,Object? required = null,Object? defaultValue = freezed,Object? min = freezed,Object? max = freezed,Object? choices = null,Object? editor = freezed,Object? secret = null,Object? description = freezed,Object? port = freezed,Object? echo = freezed,Object? scope = freezed,}) {
  return _then(ParamSpec(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,required: null == required ? _self.required : required // ignore: cast_nullable_to_non_nullable
as bool,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue ,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as num?,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as num?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as String?,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as bool,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as String?,echo: freezed == echo ? _self.echo : echo // ignore: cast_nullable_to_non_nullable
as bool?,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _ParamSpec implements ParamSpec {
  const _ParamSpec({required this.name, this.display, this.type = 'string', this.required = false, this.defaultValue, this.min, this.max, this.choices = const IListConst([]), this.editor, this.secret = false, this.description, this.port, this.echo, this.scope});
  

@override final  String name;
@override final  String? display;
/// TypeCode name (`string`, `number`, `int`, `bool`, `enum`, …).
@override@JsonKey() final  String type;
@override@JsonKey() final  bool required;
@override final  Object? defaultValue;
@override final  num? min;
@override final  num? max;
@override@JsonKey() final  IList<String> choices;
/// `file`, `textarea`, …
@override final  String? editor;
@override@JsonKey() final  bool secret;
@override final  String? description;
/// The input port that feeds it (`in.<name>`, ADR 0038 §2); null when
/// the catalog does not say or it has none.
@override final  String? port;
/// Whether it repeats as an output named like it (ADR 0038 §1); null
/// when the catalog does not say.
@override final  bool? echo;
/// The parameter that holds this field's scope (catalog
/// `params[].scope`, ADR 0040 §1: `key` → `key_scope`): a key from the
/// field's port is read only inside it.
@override final  String? scope;

/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParamSpecCopyWith<_ParamSpec> get copyWith => __$ParamSpecCopyWithImpl<_ParamSpec>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParamSpec&&(identical(other.name, name) || other.name == name)&&(identical(other.display, display) || other.display == display)&&(identical(other.type, type) || other.type == type)&&(identical(other.required, required) || other.required == required)&&const DeepCollectionEquality().equals(other.defaultValue, defaultValue)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&const DeepCollectionEquality().equals(other.choices, choices)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.secret, secret) || other.secret == secret)&&(identical(other.description, description) || other.description == description)&&(identical(other.port, port) || other.port == port)&&(identical(other.echo, echo) || other.echo == echo)&&(identical(other.scope, scope) || other.scope == scope));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,display,type,required,const DeepCollectionEquality().hash(defaultValue),min,max,const DeepCollectionEquality().hash(choices),editor,secret,description,port,echo,scope);
}

@override
String toString() {
    return 'ParamSpec(name: $name, display: $display, type: $type, required: $required, defaultValue: $defaultValue, min: $min, max: $max, choices: $choices, editor: $editor, secret: $secret, description: $description, port: $port, echo: $echo, scope: $scope)';
}


}

/// @nodoc
abstract mixin class _$ParamSpecCopyWith<$Res> implements $ParamSpecCopyWith<$Res> {
  factory _$ParamSpecCopyWith(_ParamSpec value, $Res Function(_ParamSpec) _then) = __$ParamSpecCopyWithImpl;
@override @useResult
$Res call({
 String name, String? display, String type, bool required, Object? defaultValue, num? min, num? max, IList<String> choices, String? editor, bool secret, String? description, String? port, bool? echo, String? scope
});




}
/// @nodoc
class __$ParamSpecCopyWithImpl<$Res>
    implements _$ParamSpecCopyWith<$Res> {
  __$ParamSpecCopyWithImpl(this._self, this._then);

  final _ParamSpec _self;
  final $Res Function(_ParamSpec) _then;

/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? display = freezed,Object? type = null,Object? required = null,Object? defaultValue = freezed,Object? min = freezed,Object? max = freezed,Object? choices = null,Object? editor = freezed,Object? secret = null,Object? description = freezed,Object? port = freezed,Object? echo = freezed,Object? scope = freezed,}) {
  return _then(_ParamSpec(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,display: freezed == display ? _self.display : display // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,required: null == required ? _self.required : required // ignore: cast_nullable_to_non_nullable
as bool,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue ,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as num?,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as num?,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<String>,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as String?,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as bool,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,port: freezed == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as String?,echo: freezed == echo ? _self.echo : echo // ignore: cast_nullable_to_non_nullable
as bool?,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
