// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageInfo {

 String get name; String get version;/// `process` or `wasm`.
 String get kind; String? get source; String? get sha256;/// The version in the repository index; empty for a custom package
/// (ADR 0048 §1).
 String get latest; bool get updateAvailable;/// The update to [latest] changes the store format.
 bool get changesState;/// The store format the installed version writes.
 int get state;/// The version kept for a rollback; null when none is kept.
 String? get previous;/// Until when [previous] is kept, Unix seconds.
 int get keepUntil;/// Going back to [previous] crosses a store format change.
 bool get previousChangesState;/// The last update or rollback; null before the first one.
 UpdateReport? get lastUpdate;
/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageInfoCopyWith<PackageInfo> get copyWith => _$PackageInfoCopyWithImpl<PackageInfo>(this as PackageInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256)&&(identical(other.latest, _this.latest) || other.latest == _this.latest)&&(identical(other.updateAvailable, _this.updateAvailable) || other.updateAvailable == _this.updateAvailable)&&(identical(other.changesState, _this.changesState) || other.changesState == _this.changesState)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.previous, _this.previous) || other.previous == _this.previous)&&(identical(other.keepUntil, _this.keepUntil) || other.keepUntil == _this.keepUntil)&&(identical(other.previousChangesState, _this.previousChangesState) || other.previousChangesState == _this.previousChangesState)&&(identical(other.lastUpdate, _this.lastUpdate) || other.lastUpdate == _this.lastUpdate));
}


@override
int get hashCode {
  final _this = this as PackageInfo;
  return Object.hash(runtimeType,_this.name,_this.version,_this.kind,_this.source,_this.sha256,_this.latest,_this.updateAvailable,_this.changesState,_this.state,_this.previous,_this.keepUntil,_this.previousChangesState,_this.lastUpdate);
}

@override
String toString() {
  final _this = this as PackageInfo;
  return 'PackageInfo(name: ${_this.name}, version: ${_this.version}, kind: ${_this.kind}, source: ${_this.source}, sha256: ${_this.sha256}, latest: ${_this.latest}, updateAvailable: ${_this.updateAvailable}, changesState: ${_this.changesState}, state: ${_this.state}, previous: ${_this.previous}, keepUntil: ${_this.keepUntil}, previousChangesState: ${_this.previousChangesState}, lastUpdate: ${_this.lastUpdate})';
}


}

/// @nodoc
abstract mixin class $PackageInfoCopyWith<$Res>  {
  factory $PackageInfoCopyWith(PackageInfo value, $Res Function(PackageInfo) _then) = _$PackageInfoCopyWithImpl;
@useResult
$Res call({
 String name, String version, String kind, String? source, String? sha256, String latest, bool updateAvailable, bool changesState, int state, String? previous, int keepUntil, bool previousChangesState, UpdateReport? lastUpdate
});


$UpdateReportCopyWith<$Res>? get lastUpdate;

}
/// @nodoc
class _$PackageInfoCopyWithImpl<$Res>
    implements $PackageInfoCopyWith<$Res> {
  _$PackageInfoCopyWithImpl(this._self, this._then);

  final PackageInfo _self;
  final $Res Function(PackageInfo) _then;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? version = null,Object? kind = null,Object? source = freezed,Object? sha256 = freezed,Object? latest = null,Object? updateAvailable = null,Object? changesState = null,Object? state = null,Object? previous = freezed,Object? keepUntil = null,Object? previousChangesState = null,Object? lastUpdate = freezed,}) {
  return _then(PackageInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,updateAvailable: null == updateAvailable ? _self.updateAvailable : updateAvailable // ignore: cast_nullable_to_non_nullable
as bool,changesState: null == changesState ? _self.changesState : changesState // ignore: cast_nullable_to_non_nullable
as bool,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as int,previous: freezed == previous ? _self.previous : previous // ignore: cast_nullable_to_non_nullable
as String?,keepUntil: null == keepUntil ? _self.keepUntil : keepUntil // ignore: cast_nullable_to_non_nullable
as int,previousChangesState: null == previousChangesState ? _self.previousChangesState : previousChangesState // ignore: cast_nullable_to_non_nullable
as bool,lastUpdate: freezed == lastUpdate ? _self.lastUpdate : lastUpdate // ignore: cast_nullable_to_non_nullable
as UpdateReport?,
  ));
}
/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateReportCopyWith<$Res>? get lastUpdate {
    if (_self.lastUpdate == null) {
    return null;
  }

  return $UpdateReportCopyWith<$Res>(_self.lastUpdate!, (value) {
    return _then(_self.copyWith(lastUpdate: value));
  });
}
}



/// @nodoc


class _PackageInfo implements PackageInfo {
  const _PackageInfo({required this.name, this.version = '', this.kind = 'process', this.source, this.sha256, this.latest = '', this.updateAvailable = false, this.changesState = false, this.state = 1, this.previous, this.keepUntil = 0, this.previousChangesState = false, this.lastUpdate});
  

@override final  String name;
@override@JsonKey() final  String version;
/// `process` or `wasm`.
@override@JsonKey() final  String kind;
@override final  String? source;
@override final  String? sha256;
/// The version in the repository index; empty for a custom package
/// (ADR 0048 §1).
@override@JsonKey() final  String latest;
@override@JsonKey() final  bool updateAvailable;
/// The update to [latest] changes the store format.
@override@JsonKey() final  bool changesState;
/// The store format the installed version writes.
@override@JsonKey() final  int state;
/// The version kept for a rollback; null when none is kept.
@override final  String? previous;
/// Until when [previous] is kept, Unix seconds.
@override@JsonKey() final  int keepUntil;
/// Going back to [previous] crosses a store format change.
@override@JsonKey() final  bool previousChangesState;
/// The last update or rollback; null before the first one.
@override final  UpdateReport? lastUpdate;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageInfoCopyWith<_PackageInfo> get copyWith => __$PackageInfoCopyWithImpl<_PackageInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.source, source) || other.source == source)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.latest, latest) || other.latest == latest)&&(identical(other.updateAvailable, updateAvailable) || other.updateAvailable == updateAvailable)&&(identical(other.changesState, changesState) || other.changesState == changesState)&&(identical(other.state, state) || other.state == state)&&(identical(other.previous, previous) || other.previous == previous)&&(identical(other.keepUntil, keepUntil) || other.keepUntil == keepUntil)&&(identical(other.previousChangesState, previousChangesState) || other.previousChangesState == previousChangesState)&&(identical(other.lastUpdate, lastUpdate) || other.lastUpdate == lastUpdate));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,version,kind,source,sha256,latest,updateAvailable,changesState,state,previous,keepUntil,previousChangesState,lastUpdate);
}

@override
String toString() {
    return 'PackageInfo(name: $name, version: $version, kind: $kind, source: $source, sha256: $sha256, latest: $latest, updateAvailable: $updateAvailable, changesState: $changesState, state: $state, previous: $previous, keepUntil: $keepUntil, previousChangesState: $previousChangesState, lastUpdate: $lastUpdate)';
}


}

/// @nodoc
abstract mixin class _$PackageInfoCopyWith<$Res> implements $PackageInfoCopyWith<$Res> {
  factory _$PackageInfoCopyWith(_PackageInfo value, $Res Function(_PackageInfo) _then) = __$PackageInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, String version, String kind, String? source, String? sha256, String latest, bool updateAvailable, bool changesState, int state, String? previous, int keepUntil, bool previousChangesState, UpdateReport? lastUpdate
});


@override $UpdateReportCopyWith<$Res>? get lastUpdate;

}
/// @nodoc
class __$PackageInfoCopyWithImpl<$Res>
    implements _$PackageInfoCopyWith<$Res> {
  __$PackageInfoCopyWithImpl(this._self, this._then);

  final _PackageInfo _self;
  final $Res Function(_PackageInfo) _then;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = null,Object? kind = null,Object? source = freezed,Object? sha256 = freezed,Object? latest = null,Object? updateAvailable = null,Object? changesState = null,Object? state = null,Object? previous = freezed,Object? keepUntil = null,Object? previousChangesState = null,Object? lastUpdate = freezed,}) {
  return _then(_PackageInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,updateAvailable: null == updateAvailable ? _self.updateAvailable : updateAvailable // ignore: cast_nullable_to_non_nullable
as bool,changesState: null == changesState ? _self.changesState : changesState // ignore: cast_nullable_to_non_nullable
as bool,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as int,previous: freezed == previous ? _self.previous : previous // ignore: cast_nullable_to_non_nullable
as String?,keepUntil: null == keepUntil ? _self.keepUntil : keepUntil // ignore: cast_nullable_to_non_nullable
as int,previousChangesState: null == previousChangesState ? _self.previousChangesState : previousChangesState // ignore: cast_nullable_to_non_nullable
as bool,lastUpdate: freezed == lastUpdate ? _self.lastUpdate : lastUpdate // ignore: cast_nullable_to_non_nullable
as UpdateReport?,
  ));
}

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateReportCopyWith<$Res>? get lastUpdate {
    if (_self.lastUpdate == null) {
    return null;
  }

  return $UpdateReportCopyWith<$Res>(_self.lastUpdate!, (value) {
    return _then(_self.copyWith(lastUpdate: value));
  });
}
}

// dart format on
