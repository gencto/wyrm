// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageManifest {

/// The manifest as indented JSON.
 String get pretty;/// The fields the format does not have.
 IList<String> get unknown; Stated<String> get name; Stated<String> get version;/// `wyrm_link`.
 Stated<int> get protocol;/// `process` or `wasm`; any other name is wrong.
 Stated<PackageKind> get kind;/// `entry` of a WASM package.
 Stated<String> get entry;/// `entries` of a process package: the file of each host (`os-arch`),
/// null for an entry that is not a text. Null when the manifest has no
/// map of entries.
 IMap<String, String?>? get entries;/// What the package asks for (`capabilities`, `requester`); empty
/// when [rightsProblem] says they could not be read.
 IList<RequestedRight> get rights; ManifestProblem? get rightsProblem;
/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageManifestCopyWith<PackageManifest> get copyWith => _$PackageManifestCopyWithImpl<PackageManifest>(this as PackageManifest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageManifest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageManifest&&(identical(other.pretty, _this.pretty) || other.pretty == _this.pretty)&&const DeepCollectionEquality().equals(other.unknown, _this.unknown)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.entries, _this.entries) || other.entries == _this.entries)&&const DeepCollectionEquality().equals(other.rights, _this.rights)&&(identical(other.rightsProblem, _this.rightsProblem) || other.rightsProblem == _this.rightsProblem));
}


@override
int get hashCode {
  final _this = this as PackageManifest;
  return Object.hash(runtimeType,_this.pretty,const DeepCollectionEquality().hash(_this.unknown),_this.name,_this.version,_this.protocol,_this.kind,_this.entry,_this.entries,const DeepCollectionEquality().hash(_this.rights),_this.rightsProblem);
}

@override
String toString() {
  final _this = this as PackageManifest;
  return 'PackageManifest(pretty: ${_this.pretty}, unknown: ${_this.unknown}, name: ${_this.name}, version: ${_this.version}, protocol: ${_this.protocol}, kind: ${_this.kind}, entry: ${_this.entry}, entries: ${_this.entries}, rights: ${_this.rights}, rightsProblem: ${_this.rightsProblem})';
}


}

/// @nodoc
abstract mixin class $PackageManifestCopyWith<$Res>  {
  factory $PackageManifestCopyWith(PackageManifest value, $Res Function(PackageManifest) _then) = _$PackageManifestCopyWithImpl;
@useResult
$Res call({
 String pretty, IList<String> unknown, Stated<String> name, Stated<String> version, Stated<int> protocol, Stated<PackageKind> kind, Stated<String> entry, IMap<String, String?>? entries, IList<RequestedRight> rights, ManifestProblem? rightsProblem
});


$StatedCopyWith<String, $Res> get name;$StatedCopyWith<String, $Res> get version;$StatedCopyWith<int, $Res> get protocol;$StatedCopyWith<PackageKind, $Res> get kind;$StatedCopyWith<String, $Res> get entry;$ManifestProblemCopyWith<$Res>? get rightsProblem;

}
/// @nodoc
class _$PackageManifestCopyWithImpl<$Res>
    implements $PackageManifestCopyWith<$Res> {
  _$PackageManifestCopyWithImpl(this._self, this._then);

  final PackageManifest _self;
  final $Res Function(PackageManifest) _then;

/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pretty = null,Object? unknown = null,Object? name = null,Object? version = null,Object? protocol = null,Object? kind = null,Object? entry = null,Object? entries = freezed,Object? rights = null,Object? rightsProblem = freezed,}) {
  return _then(PackageManifest(
pretty: null == pretty ? _self.pretty : pretty // ignore: cast_nullable_to_non_nullable
as String,unknown: null == unknown ? _self.unknown : unknown // ignore: cast_nullable_to_non_nullable
as IList<String>,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as Stated<String>,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as Stated<String>,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as Stated<int>,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as Stated<PackageKind>,entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as Stated<String>,entries: freezed == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as IMap<String, String?>?,rights: null == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>,rightsProblem: freezed == rightsProblem ? _self.rightsProblem : rightsProblem // ignore: cast_nullable_to_non_nullable
as ManifestProblem?,
  ));
}
/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get name {
  
  return $StatedCopyWith<String, $Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get version {
  
  return $StatedCopyWith<String, $Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<int, $Res> get protocol {
  
  return $StatedCopyWith<int, $Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<PackageKind, $Res> get kind {
  
  return $StatedCopyWith<PackageKind, $Res>(_self.kind, (value) {
    return _then(_self.copyWith(kind: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get entry {
  
  return $StatedCopyWith<String, $Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res>? get rightsProblem {
    if (_self.rightsProblem == null) {
    return null;
  }

  return $ManifestProblemCopyWith<$Res>(_self.rightsProblem!, (value) {
    return _then(_self.copyWith(rightsProblem: value));
  });
}
}



/// @nodoc


class _PackageManifest implements PackageManifest {
  const _PackageManifest({required this.pretty, required this.unknown, required this.name, required this.version, required this.protocol, required this.kind, required this.entry, this.entries, this.rights = const IListConst([]), this.rightsProblem});
  

/// The manifest as indented JSON.
@override final  String pretty;
/// The fields the format does not have.
@override final  IList<String> unknown;
@override final  Stated<String> name;
@override final  Stated<String> version;
/// `wyrm_link`.
@override final  Stated<int> protocol;
/// `process` or `wasm`; any other name is wrong.
@override final  Stated<PackageKind> kind;
/// `entry` of a WASM package.
@override final  Stated<String> entry;
/// `entries` of a process package: the file of each host (`os-arch`),
/// null for an entry that is not a text. Null when the manifest has no
/// map of entries.
@override final  IMap<String, String?>? entries;
/// What the package asks for (`capabilities`, `requester`); empty
/// when [rightsProblem] says they could not be read.
@override@JsonKey() final  IList<RequestedRight> rights;
@override final  ManifestProblem? rightsProblem;

/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageManifestCopyWith<_PackageManifest> get copyWith => __$PackageManifestCopyWithImpl<_PackageManifest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageManifest&&(identical(other.pretty, pretty) || other.pretty == pretty)&&const DeepCollectionEquality().equals(other.unknown, unknown)&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.entries, entries) || other.entries == entries)&&const DeepCollectionEquality().equals(other.rights, rights)&&(identical(other.rightsProblem, rightsProblem) || other.rightsProblem == rightsProblem));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pretty,const DeepCollectionEquality().hash(unknown),name,version,protocol,kind,entry,entries,const DeepCollectionEquality().hash(rights),rightsProblem);
}

@override
String toString() {
    return 'PackageManifest(pretty: $pretty, unknown: $unknown, name: $name, version: $version, protocol: $protocol, kind: $kind, entry: $entry, entries: $entries, rights: $rights, rightsProblem: $rightsProblem)';
}


}

/// @nodoc
abstract mixin class _$PackageManifestCopyWith<$Res> implements $PackageManifestCopyWith<$Res> {
  factory _$PackageManifestCopyWith(_PackageManifest value, $Res Function(_PackageManifest) _then) = __$PackageManifestCopyWithImpl;
@override @useResult
$Res call({
 String pretty, IList<String> unknown, Stated<String> name, Stated<String> version, Stated<int> protocol, Stated<PackageKind> kind, Stated<String> entry, IMap<String, String?>? entries, IList<RequestedRight> rights, ManifestProblem? rightsProblem
});


@override $StatedCopyWith<String, $Res> get name;@override $StatedCopyWith<String, $Res> get version;@override $StatedCopyWith<int, $Res> get protocol;@override $StatedCopyWith<PackageKind, $Res> get kind;@override $StatedCopyWith<String, $Res> get entry;@override $ManifestProblemCopyWith<$Res>? get rightsProblem;

}
/// @nodoc
class __$PackageManifestCopyWithImpl<$Res>
    implements _$PackageManifestCopyWith<$Res> {
  __$PackageManifestCopyWithImpl(this._self, this._then);

  final _PackageManifest _self;
  final $Res Function(_PackageManifest) _then;

/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pretty = null,Object? unknown = null,Object? name = null,Object? version = null,Object? protocol = null,Object? kind = null,Object? entry = null,Object? entries = freezed,Object? rights = null,Object? rightsProblem = freezed,}) {
  return _then(_PackageManifest(
pretty: null == pretty ? _self.pretty : pretty // ignore: cast_nullable_to_non_nullable
as String,unknown: null == unknown ? _self.unknown : unknown // ignore: cast_nullable_to_non_nullable
as IList<String>,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as Stated<String>,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as Stated<String>,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as Stated<int>,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as Stated<PackageKind>,entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as Stated<String>,entries: freezed == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as IMap<String, String?>?,rights: null == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>,rightsProblem: freezed == rightsProblem ? _self.rightsProblem : rightsProblem // ignore: cast_nullable_to_non_nullable
as ManifestProblem?,
  ));
}

/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get name {
  
  return $StatedCopyWith<String, $Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get version {
  
  return $StatedCopyWith<String, $Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<int, $Res> get protocol {
  
  return $StatedCopyWith<int, $Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<PackageKind, $Res> get kind {
  
  return $StatedCopyWith<PackageKind, $Res>(_self.kind, (value) {
    return _then(_self.copyWith(kind: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatedCopyWith<String, $Res> get entry {
  
  return $StatedCopyWith<String, $Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}/// Create a copy of PackageManifest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res>? get rightsProblem {
    if (_self.rightsProblem == null) {
    return null;
  }

  return $ManifestProblemCopyWith<$Res>(_self.rightsProblem!, (value) {
    return _then(_self.copyWith(rightsProblem: value));
  });
}
}

// dart format on
