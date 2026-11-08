// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'param_spec.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParamSpec {

 String get name; String? get display;/// TypeCode name (`string`, `number`, `int`, `bool`, `enum`, …).
 String get type; bool get required; Object? get defaultValue; num? get min; num? get max; IList<String> get choices;/// `file`, `textarea`, …
 String? get editor; bool get secret; String? get description;
/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParamSpecCopyWith<ParamSpec> get copyWith => _$ParamSpecCopyWithImpl<ParamSpec>(this as ParamSpec, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParamSpec&&(identical(other.name, name) || other.name == name)&&(identical(other.display, display) || other.display == display)&&(identical(other.type, type) || other.type == type)&&(identical(other.required, required) || other.required == required)&&const DeepCollectionEquality().equals(other.defaultValue, defaultValue)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&const DeepCollectionEquality().equals(other.choices, choices)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.secret, secret) || other.secret == secret)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode => Object.hash(runtimeType,name,display,type,required,const DeepCollectionEquality().hash(defaultValue),min,max,const DeepCollectionEquality().hash(choices),editor,secret,description);

@override
String toString() {
  return 'ParamSpec(name: $name, display: $display, type: $type, required: $required, defaultValue: $defaultValue, min: $min, max: $max, choices: $choices, editor: $editor, secret: $secret, description: $description)';
}


}

/// @nodoc
abstract mixin class $ParamSpecCopyWith<$Res>  {
  factory $ParamSpecCopyWith(ParamSpec value, $Res Function(ParamSpec) _then) = _$ParamSpecCopyWithImpl;
@useResult
$Res call({
 String name, String? display, String type, bool required, Object? defaultValue, num? min, num? max, IList<String> choices, String? editor, bool secret, String? description
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
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? display = freezed,Object? type = null,Object? required = null,Object? defaultValue = freezed,Object? min = freezed,Object? max = freezed,Object? choices = null,Object? editor = freezed,Object? secret = null,Object? description = freezed,}) {
  return _then(_self.copyWith(
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
as String?,
  ));
}

}



/// @nodoc


class _ParamSpec implements ParamSpec {
  const _ParamSpec({required this.name, this.display, this.type = 'string', this.required = false, this.defaultValue, this.min, this.max, this.choices = const IListConst([]), this.editor, this.secret = false, this.description});
  

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

/// Create a copy of ParamSpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParamSpecCopyWith<_ParamSpec> get copyWith => __$ParamSpecCopyWithImpl<_ParamSpec>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParamSpec&&(identical(other.name, name) || other.name == name)&&(identical(other.display, display) || other.display == display)&&(identical(other.type, type) || other.type == type)&&(identical(other.required, required) || other.required == required)&&const DeepCollectionEquality().equals(other.defaultValue, defaultValue)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&const DeepCollectionEquality().equals(other.choices, choices)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.secret, secret) || other.secret == secret)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode => Object.hash(runtimeType,name,display,type,required,const DeepCollectionEquality().hash(defaultValue),min,max,const DeepCollectionEquality().hash(choices),editor,secret,description);

@override
String toString() {
  return 'ParamSpec(name: $name, display: $display, type: $type, required: $required, defaultValue: $defaultValue, min: $min, max: $max, choices: $choices, editor: $editor, secret: $secret, description: $description)';
}


}

/// @nodoc
abstract mixin class _$ParamSpecCopyWith<$Res> implements $ParamSpecCopyWith<$Res> {
  factory _$ParamSpecCopyWith(_ParamSpec value, $Res Function(_ParamSpec) _then) = __$ParamSpecCopyWithImpl;
@override @useResult
$Res call({
 String name, String? display, String type, bool required, Object? defaultValue, num? min, num? max, IList<String> choices, String? editor, bool secret, String? description
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
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? display = freezed,Object? type = null,Object? required = null,Object? defaultValue = freezed,Object? min = freezed,Object? max = freezed,Object? choices = null,Object? editor = freezed,Object? secret = null,Object? description = freezed,}) {
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
as String?,
  ));
}


}

// dart format on
