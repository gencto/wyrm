// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'manifest_problem.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ManifestProblem {

 ManifestFault get fault; String get field; String? get found; int? get offset;
/// Create a copy of ManifestProblem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<ManifestProblem> get copyWith => _$ManifestProblemCopyWithImpl<ManifestProblem>(this as ManifestProblem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ManifestProblem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ManifestProblem&&(identical(other.fault, _this.fault) || other.fault == _this.fault)&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.found, _this.found) || other.found == _this.found)&&(identical(other.offset, _this.offset) || other.offset == _this.offset));
}


@override
int get hashCode {
  final _this = this as ManifestProblem;
  return Object.hash(runtimeType,_this.fault,_this.field,_this.found,_this.offset);
}

@override
String toString() {
  final _this = this as ManifestProblem;
  return 'ManifestProblem(fault: ${_this.fault}, field: ${_this.field}, found: ${_this.found}, offset: ${_this.offset})';
}


}

/// @nodoc
abstract mixin class $ManifestProblemCopyWith<$Res>  {
  factory $ManifestProblemCopyWith(ManifestProblem value, $Res Function(ManifestProblem) _then) = _$ManifestProblemCopyWithImpl;
@useResult
$Res call({
 ManifestFault fault, String field, String? found, int? offset
});




}
/// @nodoc
class _$ManifestProblemCopyWithImpl<$Res>
    implements $ManifestProblemCopyWith<$Res> {
  _$ManifestProblemCopyWithImpl(this._self, this._then);

  final ManifestProblem _self;
  final $Res Function(ManifestProblem) _then;

/// Create a copy of ManifestProblem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fault = null,Object? field = null,Object? found = freezed,Object? offset = freezed,}) {
  return _then(ManifestProblem(
fault: null == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as ManifestFault,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,found: freezed == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as String?,offset: freezed == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}



/// @nodoc


class _ManifestProblem implements ManifestProblem {
  const _ManifestProblem({required this.fault, this.field = '', this.found, this.offset});
  

@override final  ManifestFault fault;
@override@JsonKey() final  String field;
@override final  String? found;
@override final  int? offset;

/// Create a copy of ManifestProblem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ManifestProblemCopyWith<_ManifestProblem> get copyWith => __$ManifestProblemCopyWithImpl<_ManifestProblem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ManifestProblem&&(identical(other.fault, fault) || other.fault == fault)&&(identical(other.field, field) || other.field == field)&&(identical(other.found, found) || other.found == found)&&(identical(other.offset, offset) || other.offset == offset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fault,field,found,offset);
}

@override
String toString() {
    return 'ManifestProblem(fault: $fault, field: $field, found: $found, offset: $offset)';
}


}

/// @nodoc
abstract mixin class _$ManifestProblemCopyWith<$Res> implements $ManifestProblemCopyWith<$Res> {
  factory _$ManifestProblemCopyWith(_ManifestProblem value, $Res Function(_ManifestProblem) _then) = __$ManifestProblemCopyWithImpl;
@override @useResult
$Res call({
 ManifestFault fault, String field, String? found, int? offset
});




}
/// @nodoc
class __$ManifestProblemCopyWithImpl<$Res>
    implements _$ManifestProblemCopyWith<$Res> {
  __$ManifestProblemCopyWithImpl(this._self, this._then);

  final _ManifestProblem _self;
  final $Res Function(_ManifestProblem) _then;

/// Create a copy of ManifestProblem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fault = null,Object? field = null,Object? found = freezed,Object? offset = freezed,}) {
  return _then(_ManifestProblem(
fault: null == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as ManifestFault,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,found: freezed == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as String?,offset: freezed == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
