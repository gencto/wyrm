// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'schema_pair.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SchemaPair {

 int get backup; int get here;
/// Create a copy of SchemaPair
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SchemaPairCopyWith<SchemaPair> get copyWith => _$SchemaPairCopyWithImpl<SchemaPair>(this as SchemaPair, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SchemaPair;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SchemaPair&&(identical(other.backup, _this.backup) || other.backup == _this.backup)&&(identical(other.here, _this.here) || other.here == _this.here));
}


@override
int get hashCode {
  final _this = this as SchemaPair;
  return Object.hash(runtimeType,_this.backup,_this.here);
}

@override
String toString() {
  final _this = this as SchemaPair;
  return 'SchemaPair(backup: ${_this.backup}, here: ${_this.here})';
}


}

/// @nodoc
abstract mixin class $SchemaPairCopyWith<$Res>  {
  factory $SchemaPairCopyWith(SchemaPair value, $Res Function(SchemaPair) _then) = _$SchemaPairCopyWithImpl;
@useResult
$Res call({
 int backup, int here
});




}
/// @nodoc
class _$SchemaPairCopyWithImpl<$Res>
    implements $SchemaPairCopyWith<$Res> {
  _$SchemaPairCopyWithImpl(this._self, this._then);

  final SchemaPair _self;
  final $Res Function(SchemaPair) _then;

/// Create a copy of SchemaPair
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? backup = null,Object? here = null,}) {
  return _then(SchemaPair(
backup: null == backup ? _self.backup : backup // ignore: cast_nullable_to_non_nullable
as int,here: null == here ? _self.here : here // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _SchemaPair implements SchemaPair {
  const _SchemaPair({required this.backup, required this.here});
  

@override final  int backup;
@override final  int here;

/// Create a copy of SchemaPair
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SchemaPairCopyWith<_SchemaPair> get copyWith => __$SchemaPairCopyWithImpl<_SchemaPair>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SchemaPair&&(identical(other.backup, backup) || other.backup == backup)&&(identical(other.here, here) || other.here == here));
}


@override
int get hashCode {
    return Object.hash(runtimeType,backup,here);
}

@override
String toString() {
    return 'SchemaPair(backup: $backup, here: $here)';
}


}

/// @nodoc
abstract mixin class _$SchemaPairCopyWith<$Res> implements $SchemaPairCopyWith<$Res> {
  factory _$SchemaPairCopyWith(_SchemaPair value, $Res Function(_SchemaPair) _then) = __$SchemaPairCopyWithImpl;
@override @useResult
$Res call({
 int backup, int here
});




}
/// @nodoc
class __$SchemaPairCopyWithImpl<$Res>
    implements _$SchemaPairCopyWith<$Res> {
  __$SchemaPairCopyWithImpl(this._self, this._then);

  final _SchemaPair _self;
  final $Res Function(_SchemaPair) _then;

/// Create a copy of SchemaPair
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? backup = null,Object? here = null,}) {
  return _then(_SchemaPair(
backup: null == backup ? _self.backup : backup // ignore: cast_nullable_to_non_nullable
as int,here: null == here ? _self.here : here // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
