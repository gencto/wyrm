// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'packages_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackagesState {

 IMap<String, PackageInfo> get table; IList<String> get view;
/// Create a copy of PackagesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackagesStateCopyWith<PackagesState> get copyWith => _$PackagesStateCopyWithImpl<PackagesState>(this as PackagesState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackagesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view));

@override
String toString() {
  return 'PackagesState(table: $table, view: $view)';
}


}

/// @nodoc
abstract mixin class $PackagesStateCopyWith<$Res>  {
  factory $PackagesStateCopyWith(PackagesState value, $Res Function(PackagesState) _then) = _$PackagesStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, PackageInfo> table, IList<String> view
});




}
/// @nodoc
class _$PackagesStateCopyWithImpl<$Res>
    implements $PackagesStateCopyWith<$Res> {
  _$PackagesStateCopyWithImpl(this._self, this._then);

  final PackagesState _self;
  final $Res Function(PackagesState) _then;

/// Create a copy of PackagesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, PackageInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _PackagesState implements PackagesState {
  const _PackagesState({this.table = const IMapConst({}), this.view = const IListConst([])});
  

@override@JsonKey() final  IMap<String, PackageInfo> table;
@override@JsonKey() final  IList<String> view;

/// Create a copy of PackagesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackagesStateCopyWith<_PackagesState> get copyWith => __$PackagesStateCopyWithImpl<_PackagesState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackagesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view));

@override
String toString() {
  return 'PackagesState(table: $table, view: $view)';
}


}

/// @nodoc
abstract mixin class _$PackagesStateCopyWith<$Res> implements $PackagesStateCopyWith<$Res> {
  factory _$PackagesStateCopyWith(_PackagesState value, $Res Function(_PackagesState) _then) = __$PackagesStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, PackageInfo> table, IList<String> view
});




}
/// @nodoc
class __$PackagesStateCopyWithImpl<$Res>
    implements _$PackagesStateCopyWith<$Res> {
  __$PackagesStateCopyWithImpl(this._self, this._then);

  final _PackagesState _self;
  final $Res Function(_PackagesState) _then;

/// Create a copy of PackagesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,}) {
  return _then(_PackagesState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, PackageInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
