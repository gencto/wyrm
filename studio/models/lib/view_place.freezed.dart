// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'view_place.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ViewPlace {

 String get page; IMap<String, String> get params;
/// Create a copy of ViewPlace
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ViewPlaceCopyWith<ViewPlace> get copyWith => _$ViewPlaceCopyWithImpl<ViewPlace>(this as ViewPlace, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ViewPlace;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ViewPlace&&(identical(other.page, _this.page) || other.page == _this.page)&&(identical(other.params, _this.params) || other.params == _this.params));
}


@override
int get hashCode {
  final _this = this as ViewPlace;
  return Object.hash(runtimeType,_this.page,_this.params);
}

@override
String toString() {
  final _this = this as ViewPlace;
  return 'ViewPlace(page: ${_this.page}, params: ${_this.params})';
}


}

/// @nodoc
abstract mixin class $ViewPlaceCopyWith<$Res>  {
  factory $ViewPlaceCopyWith(ViewPlace value, $Res Function(ViewPlace) _then) = _$ViewPlaceCopyWithImpl;
@useResult
$Res call({
 String page, IMap<String, String> params
});




}
/// @nodoc
class _$ViewPlaceCopyWithImpl<$Res>
    implements $ViewPlaceCopyWith<$Res> {
  _$ViewPlaceCopyWithImpl(this._self, this._then);

  final ViewPlace _self;
  final $Res Function(ViewPlace) _then;

/// Create a copy of ViewPlace
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? page = null,Object? params = null,}) {
  return _then(ViewPlace(
page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}

}



/// @nodoc


class _ViewPlace implements ViewPlace {
  const _ViewPlace({required this.page, this.params = const IMapConst({})});
  

@override final  String page;
@override@JsonKey() final  IMap<String, String> params;

/// Create a copy of ViewPlace
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ViewPlaceCopyWith<_ViewPlace> get copyWith => __$ViewPlaceCopyWithImpl<_ViewPlace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ViewPlace&&(identical(other.page, page) || other.page == page)&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode {
    return Object.hash(runtimeType,page,params);
}

@override
String toString() {
    return 'ViewPlace(page: $page, params: $params)';
}


}

/// @nodoc
abstract mixin class _$ViewPlaceCopyWith<$Res> implements $ViewPlaceCopyWith<$Res> {
  factory _$ViewPlaceCopyWith(_ViewPlace value, $Res Function(_ViewPlace) _then) = __$ViewPlaceCopyWithImpl;
@override @useResult
$Res call({
 String page, IMap<String, String> params
});




}
/// @nodoc
class __$ViewPlaceCopyWithImpl<$Res>
    implements _$ViewPlaceCopyWith<$Res> {
  __$ViewPlaceCopyWithImpl(this._self, this._then);

  final _ViewPlace _self;
  final $Res Function(_ViewPlace) _then;

/// Create a copy of ViewPlace
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? page = null,Object? params = null,}) {
  return _then(_ViewPlace(
page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}


}

// dart format on
