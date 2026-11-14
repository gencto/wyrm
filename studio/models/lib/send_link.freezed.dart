// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'send_link.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SendLink {

 String get link; String get folder;
/// Create a copy of SendLink
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SendLinkCopyWith<SendLink> get copyWith => _$SendLinkCopyWithImpl<SendLink>(this as SendLink, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SendLink;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SendLink&&(identical(other.link, _this.link) || other.link == _this.link)&&(identical(other.folder, _this.folder) || other.folder == _this.folder));
}


@override
int get hashCode {
  final _this = this as SendLink;
  return Object.hash(runtimeType,_this.link,_this.folder);
}

@override
String toString() {
  final _this = this as SendLink;
  return 'SendLink(link: ${_this.link}, folder: ${_this.folder})';
}


}

/// @nodoc
abstract mixin class $SendLinkCopyWith<$Res>  {
  factory $SendLinkCopyWith(SendLink value, $Res Function(SendLink) _then) = _$SendLinkCopyWithImpl;
@useResult
$Res call({
 String link, String folder
});




}
/// @nodoc
class _$SendLinkCopyWithImpl<$Res>
    implements $SendLinkCopyWith<$Res> {
  _$SendLinkCopyWithImpl(this._self, this._then);

  final SendLink _self;
  final $Res Function(SendLink) _then;

/// Create a copy of SendLink
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? link = null,Object? folder = null,}) {
  return _then(SendLink(
link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _SendLink implements SendLink {
  const _SendLink({required this.link, this.folder = 'backups'});
  

@override final  String link;
@override@JsonKey() final  String folder;

/// Create a copy of SendLink
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SendLinkCopyWith<_SendLink> get copyWith => __$SendLinkCopyWithImpl<_SendLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SendLink&&(identical(other.link, link) || other.link == link)&&(identical(other.folder, folder) || other.folder == folder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,link,folder);
}

@override
String toString() {
    return 'SendLink(link: $link, folder: $folder)';
}


}

/// @nodoc
abstract mixin class _$SendLinkCopyWith<$Res> implements $SendLinkCopyWith<$Res> {
  factory _$SendLinkCopyWith(_SendLink value, $Res Function(_SendLink) _then) = __$SendLinkCopyWithImpl;
@override @useResult
$Res call({
 String link, String folder
});




}
/// @nodoc
class __$SendLinkCopyWithImpl<$Res>
    implements _$SendLinkCopyWith<$Res> {
  __$SendLinkCopyWithImpl(this._self, this._then);

  final _SendLink _self;
  final $Res Function(_SendLink) _then;

/// Create a copy of SendLink
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? link = null,Object? folder = null,}) {
  return _then(_SendLink(
link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
