// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'studio_notice.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StudioNotice {

/// From the same counter as `StudioError.id`, so the toasts keep the
/// order they came in.
 int get id;/// The words, when the one who said it has them; empty for a [kind]
/// whose words `ui` says.
 String get title;/// What the notice says, when `ui` words it (with [count]).
 NoticeKind? get kind; int get count;/// One line under the title.
 String? get detail;
/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioNoticeCopyWith<StudioNotice> get copyWith => _$StudioNoticeCopyWithImpl<StudioNotice>(this as StudioNotice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioNotice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioNotice&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.count, _this.count) || other.count == _this.count)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as StudioNotice;
  return Object.hash(runtimeType,_this.id,_this.title,_this.kind,_this.count,_this.detail);
}

@override
String toString() {
  final _this = this as StudioNotice;
  return 'StudioNotice(id: ${_this.id}, title: ${_this.title}, kind: ${_this.kind}, count: ${_this.count}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $StudioNoticeCopyWith<$Res>  {
  factory $StudioNoticeCopyWith(StudioNotice value, $Res Function(StudioNotice) _then) = _$StudioNoticeCopyWithImpl;
@useResult
$Res call({
 int id, String title, NoticeKind? kind, int count, String? detail
});




}
/// @nodoc
class _$StudioNoticeCopyWithImpl<$Res>
    implements $StudioNoticeCopyWith<$Res> {
  _$StudioNoticeCopyWithImpl(this._self, this._then);

  final StudioNotice _self;
  final $Res Function(StudioNotice) _then;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? kind = freezed,Object? count = null,Object? detail = freezed,}) {
  return _then(StudioNotice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as NoticeKind?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _StudioNotice implements StudioNotice {
  const _StudioNotice({required this.id, this.title = '', this.kind, this.count = 0, this.detail});
  

/// From the same counter as `StudioError.id`, so the toasts keep the
/// order they came in.
@override final  int id;
/// The words, when the one who said it has them; empty for a [kind]
/// whose words `ui` says.
@override@JsonKey() final  String title;
/// What the notice says, when `ui` words it (with [count]).
@override final  NoticeKind? kind;
@override@JsonKey() final  int count;
/// One line under the title.
@override final  String? detail;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioNoticeCopyWith<_StudioNotice> get copyWith => __$StudioNoticeCopyWithImpl<_StudioNotice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioNotice&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.count, count) || other.count == count)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,kind,count,detail);
}

@override
String toString() {
    return 'StudioNotice(id: $id, title: $title, kind: $kind, count: $count, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$StudioNoticeCopyWith<$Res> implements $StudioNoticeCopyWith<$Res> {
  factory _$StudioNoticeCopyWith(_StudioNotice value, $Res Function(_StudioNotice) _then) = __$StudioNoticeCopyWithImpl;
@override @useResult
$Res call({
 int id, String title, NoticeKind? kind, int count, String? detail
});




}
/// @nodoc
class __$StudioNoticeCopyWithImpl<$Res>
    implements _$StudioNoticeCopyWith<$Res> {
  __$StudioNoticeCopyWithImpl(this._self, this._then);

  final _StudioNotice _self;
  final $Res Function(_StudioNotice) _then;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? kind = freezed,Object? count = null,Object? detail = freezed,}) {
  return _then(_StudioNotice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as NoticeKind?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
