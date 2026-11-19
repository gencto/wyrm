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
 int get id;/// What it says, when it is not a [system] notice; `ui` words it.
 NoticeKind? get kind;/// How many keys were copied ([NoticeKind.keysCopied]).
 int get count;/// Where a file went ([NoticeKind.planSaved]).
 String? get path;/// The arguments a saved plan left out ([NoticeKind.planSaved]).
 IList<WithheldArgs> get leftOut;/// A notice of System, worded by `ui`.
 SystemNotice? get system;
/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioNoticeCopyWith<StudioNotice> get copyWith => _$StudioNoticeCopyWithImpl<StudioNotice>(this as StudioNotice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioNotice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioNotice&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.count, _this.count) || other.count == _this.count)&&(identical(other.path, _this.path) || other.path == _this.path)&&const DeepCollectionEquality().equals(other.leftOut, _this.leftOut)&&(identical(other.system, _this.system) || other.system == _this.system));
}


@override
int get hashCode {
  final _this = this as StudioNotice;
  return Object.hash(runtimeType,_this.id,_this.kind,_this.count,_this.path,const DeepCollectionEquality().hash(_this.leftOut),_this.system);
}

@override
String toString() {
  final _this = this as StudioNotice;
  return 'StudioNotice(id: ${_this.id}, kind: ${_this.kind}, count: ${_this.count}, path: ${_this.path}, leftOut: ${_this.leftOut}, system: ${_this.system})';
}


}

/// @nodoc
abstract mixin class $StudioNoticeCopyWith<$Res>  {
  factory $StudioNoticeCopyWith(StudioNotice value, $Res Function(StudioNotice) _then) = _$StudioNoticeCopyWithImpl;
@useResult
$Res call({
 int id, NoticeKind? kind, int count, String? path, IList<WithheldArgs> leftOut, SystemNotice? system
});


$SystemNoticeCopyWith<$Res>? get system;

}
/// @nodoc
class _$StudioNoticeCopyWithImpl<$Res>
    implements $StudioNoticeCopyWith<$Res> {
  _$StudioNoticeCopyWithImpl(this._self, this._then);

  final StudioNotice _self;
  final $Res Function(StudioNotice) _then;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = freezed,Object? count = null,Object? path = freezed,Object? leftOut = null,Object? system = freezed,}) {
  return _then(StudioNotice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as NoticeKind?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,leftOut: null == leftOut ? _self.leftOut : leftOut // ignore: cast_nullable_to_non_nullable
as IList<WithheldArgs>,system: freezed == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as SystemNotice?,
  ));
}
/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SystemNoticeCopyWith<$Res>? get system {
    if (_self.system == null) {
    return null;
  }

  return $SystemNoticeCopyWith<$Res>(_self.system!, (value) {
    return _then(_self.copyWith(system: value));
  });
}
}



/// @nodoc


class _StudioNotice implements StudioNotice {
  const _StudioNotice({required this.id, this.kind, this.count = 0, this.path, this.leftOut = const IListConst([]), this.system});
  

/// From the same counter as `StudioError.id`, so the toasts keep the
/// order they came in.
@override final  int id;
/// What it says, when it is not a [system] notice; `ui` words it.
@override final  NoticeKind? kind;
/// How many keys were copied ([NoticeKind.keysCopied]).
@override@JsonKey() final  int count;
/// Where a file went ([NoticeKind.planSaved]).
@override final  String? path;
/// The arguments a saved plan left out ([NoticeKind.planSaved]).
@override@JsonKey() final  IList<WithheldArgs> leftOut;
/// A notice of System, worded by `ui`.
@override final  SystemNotice? system;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioNoticeCopyWith<_StudioNotice> get copyWith => __$StudioNoticeCopyWithImpl<_StudioNotice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioNotice&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.count, count) || other.count == count)&&(identical(other.path, path) || other.path == path)&&const DeepCollectionEquality().equals(other.leftOut, leftOut)&&(identical(other.system, system) || other.system == system));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,kind,count,path,const DeepCollectionEquality().hash(leftOut),system);
}

@override
String toString() {
    return 'StudioNotice(id: $id, kind: $kind, count: $count, path: $path, leftOut: $leftOut, system: $system)';
}


}

/// @nodoc
abstract mixin class _$StudioNoticeCopyWith<$Res> implements $StudioNoticeCopyWith<$Res> {
  factory _$StudioNoticeCopyWith(_StudioNotice value, $Res Function(_StudioNotice) _then) = __$StudioNoticeCopyWithImpl;
@override @useResult
$Res call({
 int id, NoticeKind? kind, int count, String? path, IList<WithheldArgs> leftOut, SystemNotice? system
});


@override $SystemNoticeCopyWith<$Res>? get system;

}
/// @nodoc
class __$StudioNoticeCopyWithImpl<$Res>
    implements _$StudioNoticeCopyWith<$Res> {
  __$StudioNoticeCopyWithImpl(this._self, this._then);

  final _StudioNotice _self;
  final $Res Function(_StudioNotice) _then;

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = freezed,Object? count = null,Object? path = freezed,Object? leftOut = null,Object? system = freezed,}) {
  return _then(_StudioNotice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as NoticeKind?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,leftOut: null == leftOut ? _self.leftOut : leftOut // ignore: cast_nullable_to_non_nullable
as IList<WithheldArgs>,system: freezed == system ? _self.system : system // ignore: cast_nullable_to_non_nullable
as SystemNotice?,
  ));
}

/// Create a copy of StudioNotice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SystemNoticeCopyWith<$Res>? get system {
    if (_self.system == null) {
    return null;
  }

  return $SystemNoticeCopyWith<$Res>(_self.system!, (value) {
    return _then(_self.copyWith(system: value));
  });
}
}

// dart format on
