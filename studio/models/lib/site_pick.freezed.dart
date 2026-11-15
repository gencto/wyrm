// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'site_pick.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SitePick {

 SiteNode get node; String get name;
/// Create a copy of SitePick
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SitePickCopyWith<SitePick> get copyWith => _$SitePickCopyWithImpl<SitePick>(this as SitePick, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SitePick;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SitePick&&(identical(other.node, _this.node) || other.node == _this.node)&&(identical(other.name, _this.name) || other.name == _this.name));
}


@override
int get hashCode {
  final _this = this as SitePick;
  return Object.hash(runtimeType,_this.node,_this.name);
}

@override
String toString() {
  final _this = this as SitePick;
  return 'SitePick(node: ${_this.node}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $SitePickCopyWith<$Res>  {
  factory $SitePickCopyWith(SitePick value, $Res Function(SitePick) _then) = _$SitePickCopyWithImpl;
@useResult
$Res call({
 SiteNode node, String name
});




}
/// @nodoc
class _$SitePickCopyWithImpl<$Res>
    implements $SitePickCopyWith<$Res> {
  _$SitePickCopyWithImpl(this._self, this._then);

  final SitePick _self;
  final $Res Function(SitePick) _then;

/// Create a copy of SitePick
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? node = null,Object? name = null,}) {
  return _then(SitePick(
null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as SiteNode,null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _SitePick implements SitePick {
  const _SitePick(this.node, this.name);
  

@override final  SiteNode node;
@override final  String name;

/// Create a copy of SitePick
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SitePickCopyWith<_SitePick> get copyWith => __$SitePickCopyWithImpl<_SitePick>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SitePick&&(identical(other.node, node) || other.node == node)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,node,name);
}

@override
String toString() {
    return 'SitePick(node: $node, name: $name)';
}


}

/// @nodoc
abstract mixin class _$SitePickCopyWith<$Res> implements $SitePickCopyWith<$Res> {
  factory _$SitePickCopyWith(_SitePick value, $Res Function(_SitePick) _then) = __$SitePickCopyWithImpl;
@override @useResult
$Res call({
 SiteNode node, String name
});




}
/// @nodoc
class __$SitePickCopyWithImpl<$Res>
    implements _$SitePickCopyWith<$Res> {
  __$SitePickCopyWithImpl(this._self, this._then);

  final _SitePick _self;
  final $Res Function(_SitePick) _then;

/// Create a copy of SitePick
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? node = null,Object? name = null,}) {
  return _then(_SitePick(
null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as SiteNode,null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
