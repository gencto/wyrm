// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'link_install_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkInstallState {

 int get step; InstallSource? get source; String? get item; String? get broker; LinkMode? get mode; String? get name; bool get acceptRights; IList<PackageCheck> get checks; String? get message; String get path; String get category; String? get query; String? get phase; String? get manifest; String? get rights; IList<CatalogItem> get catalog; IList<InstallTarget> get targets; String get method; String? get refusedField; String? get refusedSaid;
/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkInstallStateCopyWith<LinkInstallState> get copyWith => _$LinkInstallStateCopyWithImpl<LinkInstallState>(this as LinkInstallState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LinkInstallState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkInstallState&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.item, _this.item) || other.item == _this.item)&&(identical(other.broker, _this.broker) || other.broker == _this.broker)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.acceptRights, _this.acceptRights) || other.acceptRights == _this.acceptRights)&&const DeepCollectionEquality().equals(other.checks, _this.checks)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.manifest, _this.manifest) || other.manifest == _this.manifest)&&(identical(other.rights, _this.rights) || other.rights == _this.rights)&&const DeepCollectionEquality().equals(other.catalog, _this.catalog)&&const DeepCollectionEquality().equals(other.targets, _this.targets)&&(identical(other.method, _this.method) || other.method == _this.method)&&(identical(other.refusedField, _this.refusedField) || other.refusedField == _this.refusedField)&&(identical(other.refusedSaid, _this.refusedSaid) || other.refusedSaid == _this.refusedSaid));
}


@override
int get hashCode {
  final _this = this as LinkInstallState;
  return Object.hashAll([runtimeType,_this.step,_this.source,_this.item,_this.broker,_this.mode,_this.name,_this.acceptRights,const DeepCollectionEquality().hash(_this.checks),_this.message,_this.path,_this.category,_this.query,_this.phase,_this.manifest,_this.rights,const DeepCollectionEquality().hash(_this.catalog),const DeepCollectionEquality().hash(_this.targets),_this.method,_this.refusedField,_this.refusedSaid]);
}

@override
String toString() {
  final _this = this as LinkInstallState;
  return 'LinkInstallState(step: ${_this.step}, source: ${_this.source}, item: ${_this.item}, broker: ${_this.broker}, mode: ${_this.mode}, name: ${_this.name}, acceptRights: ${_this.acceptRights}, checks: ${_this.checks}, message: ${_this.message}, path: ${_this.path}, category: ${_this.category}, query: ${_this.query}, phase: ${_this.phase}, manifest: ${_this.manifest}, rights: ${_this.rights}, catalog: ${_this.catalog}, targets: ${_this.targets}, method: ${_this.method}, refusedField: ${_this.refusedField}, refusedSaid: ${_this.refusedSaid})';
}


}

/// @nodoc
abstract mixin class $LinkInstallStateCopyWith<$Res>  {
  factory $LinkInstallStateCopyWith(LinkInstallState value, $Res Function(LinkInstallState) _then) = _$LinkInstallStateCopyWithImpl;
@useResult
$Res call({
 int step, InstallSource? source, String? item, String? broker, LinkMode? mode, String? name, bool acceptRights, IList<PackageCheck> checks, String? message, String path, String category, String? query, String? phase, String? manifest, String? rights, IList<CatalogItem> catalog, IList<InstallTarget> targets, String method, String? refusedField, String? refusedSaid
});


$InstallSourceCopyWith<$Res>? get source;

}
/// @nodoc
class _$LinkInstallStateCopyWithImpl<$Res>
    implements $LinkInstallStateCopyWith<$Res> {
  _$LinkInstallStateCopyWithImpl(this._self, this._then);

  final LinkInstallState _self;
  final $Res Function(LinkInstallState) _then;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? source = freezed,Object? item = freezed,Object? broker = freezed,Object? mode = freezed,Object? name = freezed,Object? acceptRights = null,Object? checks = null,Object? message = freezed,Object? path = null,Object? category = null,Object? query = freezed,Object? phase = freezed,Object? manifest = freezed,Object? rights = freezed,Object? catalog = null,Object? targets = null,Object? method = null,Object? refusedField = freezed,Object? refusedSaid = freezed,}) {
  return _then(LinkInstallState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as InstallSource?,item: freezed == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as String?,broker: freezed == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String?,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,query: freezed == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String?,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,manifest: freezed == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as String?,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as String?,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as IList<CatalogItem>,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as IList<InstallTarget>,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,refusedField: freezed == refusedField ? _self.refusedField : refusedField // ignore: cast_nullable_to_non_nullable
as String?,refusedSaid: freezed == refusedSaid ? _self.refusedSaid : refusedSaid // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstallSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $InstallSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}



/// @nodoc


class _LinkInstallState implements LinkInstallState {
  const _LinkInstallState({this.step = 1, this.source, this.item, this.broker, this.mode, this.name, this.acceptRights = false, this.checks = const IListConst([]), this.message, this.path = 'official', this.category = 'All', this.query, this.phase, this.manifest, this.rights, this.catalog = const IListConst([]), this.targets = const IListConst([]), this.method = 'zip', this.refusedField, this.refusedSaid});
  

@override@JsonKey() final  int step;
@override final  InstallSource? source;
@override final  String? item;
@override final  String? broker;
@override final  LinkMode? mode;
@override final  String? name;
@override@JsonKey() final  bool acceptRights;
@override@JsonKey() final  IList<PackageCheck> checks;
@override final  String? message;
@override@JsonKey() final  String path;
@override@JsonKey() final  String category;
@override final  String? query;
@override final  String? phase;
@override final  String? manifest;
@override final  String? rights;
@override@JsonKey() final  IList<CatalogItem> catalog;
@override@JsonKey() final  IList<InstallTarget> targets;
@override@JsonKey() final  String method;
@override final  String? refusedField;
@override final  String? refusedSaid;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinkInstallStateCopyWith<_LinkInstallState> get copyWith => __$LinkInstallStateCopyWithImpl<_LinkInstallState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinkInstallState&&(identical(other.step, step) || other.step == step)&&(identical(other.source, source) || other.source == source)&&(identical(other.item, item) || other.item == item)&&(identical(other.broker, broker) || other.broker == broker)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.name, name) || other.name == name)&&(identical(other.acceptRights, acceptRights) || other.acceptRights == acceptRights)&&const DeepCollectionEquality().equals(other.checks, checks)&&(identical(other.message, message) || other.message == message)&&(identical(other.path, path) || other.path == path)&&(identical(other.category, category) || other.category == category)&&(identical(other.query, query) || other.query == query)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.manifest, manifest) || other.manifest == manifest)&&(identical(other.rights, rights) || other.rights == rights)&&const DeepCollectionEquality().equals(other.catalog, catalog)&&const DeepCollectionEquality().equals(other.targets, targets)&&(identical(other.method, method) || other.method == method)&&(identical(other.refusedField, refusedField) || other.refusedField == refusedField)&&(identical(other.refusedSaid, refusedSaid) || other.refusedSaid == refusedSaid));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,step,source,item,broker,mode,name,acceptRights,const DeepCollectionEquality().hash(checks),message,path,category,query,phase,manifest,rights,const DeepCollectionEquality().hash(catalog),const DeepCollectionEquality().hash(targets),method,refusedField,refusedSaid]);
}

@override
String toString() {
    return 'LinkInstallState(step: $step, source: $source, item: $item, broker: $broker, mode: $mode, name: $name, acceptRights: $acceptRights, checks: $checks, message: $message, path: $path, category: $category, query: $query, phase: $phase, manifest: $manifest, rights: $rights, catalog: $catalog, targets: $targets, method: $method, refusedField: $refusedField, refusedSaid: $refusedSaid)';
}


}

/// @nodoc
abstract mixin class _$LinkInstallStateCopyWith<$Res> implements $LinkInstallStateCopyWith<$Res> {
  factory _$LinkInstallStateCopyWith(_LinkInstallState value, $Res Function(_LinkInstallState) _then) = __$LinkInstallStateCopyWithImpl;
@override @useResult
$Res call({
 int step, InstallSource? source, String? item, String? broker, LinkMode? mode, String? name, bool acceptRights, IList<PackageCheck> checks, String? message, String path, String category, String? query, String? phase, String? manifest, String? rights, IList<CatalogItem> catalog, IList<InstallTarget> targets, String method, String? refusedField, String? refusedSaid
});


@override $InstallSourceCopyWith<$Res>? get source;

}
/// @nodoc
class __$LinkInstallStateCopyWithImpl<$Res>
    implements _$LinkInstallStateCopyWith<$Res> {
  __$LinkInstallStateCopyWithImpl(this._self, this._then);

  final _LinkInstallState _self;
  final $Res Function(_LinkInstallState) _then;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? step = null,Object? source = freezed,Object? item = freezed,Object? broker = freezed,Object? mode = freezed,Object? name = freezed,Object? acceptRights = null,Object? checks = null,Object? message = freezed,Object? path = null,Object? category = null,Object? query = freezed,Object? phase = freezed,Object? manifest = freezed,Object? rights = freezed,Object? catalog = null,Object? targets = null,Object? method = null,Object? refusedField = freezed,Object? refusedSaid = freezed,}) {
  return _then(_LinkInstallState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as InstallSource?,item: freezed == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as String?,broker: freezed == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String?,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,query: freezed == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String?,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,manifest: freezed == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as String?,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as String?,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as IList<CatalogItem>,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as IList<InstallTarget>,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,refusedField: freezed == refusedField ? _self.refusedField : refusedField // ignore: cast_nullable_to_non_nullable
as String?,refusedSaid: freezed == refusedSaid ? _self.refusedSaid : refusedSaid // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstallSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $InstallSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

// dart format on
