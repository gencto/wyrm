// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'install_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InstallSource {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSource);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InstallSource()';
}


}

/// @nodoc
class $InstallSourceCopyWith<$Res>  {
$InstallSourceCopyWith(InstallSource _, $Res Function(InstallSource) __);
}



/// @nodoc


class InstallSourceBuiltIn implements InstallSource {
  const InstallSourceBuiltIn({required this.driver});
  

 final  String driver;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceBuiltInCopyWith<InstallSourceBuiltIn> get copyWith => _$InstallSourceBuiltInCopyWithImpl<InstallSourceBuiltIn>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceBuiltIn&&(identical(other.driver, driver) || other.driver == driver));
}


@override
int get hashCode => Object.hash(runtimeType,driver);

@override
String toString() {
  return 'InstallSource.builtIn(driver: $driver)';
}


}

/// @nodoc
abstract mixin class $InstallSourceBuiltInCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceBuiltInCopyWith(InstallSourceBuiltIn value, $Res Function(InstallSourceBuiltIn) _then) = _$InstallSourceBuiltInCopyWithImpl;
@useResult
$Res call({
 String driver
});




}
/// @nodoc
class _$InstallSourceBuiltInCopyWithImpl<$Res>
    implements $InstallSourceBuiltInCopyWith<$Res> {
  _$InstallSourceBuiltInCopyWithImpl(this._self, this._then);

  final InstallSourceBuiltIn _self;
  final $Res Function(InstallSourceBuiltIn) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? driver = null,}) {
  return _then(InstallSourceBuiltIn(
driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InstallSourceRepository implements InstallSource {
  const InstallSourceRepository({required this.package, this.version});
  

 final  String package;
 final  String? version;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceRepositoryCopyWith<InstallSourceRepository> get copyWith => _$InstallSourceRepositoryCopyWithImpl<InstallSourceRepository>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceRepository&&(identical(other.package, package) || other.package == package)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode => Object.hash(runtimeType,package,version);

@override
String toString() {
  return 'InstallSource.repository(package: $package, version: $version)';
}


}

/// @nodoc
abstract mixin class $InstallSourceRepositoryCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceRepositoryCopyWith(InstallSourceRepository value, $Res Function(InstallSourceRepository) _then) = _$InstallSourceRepositoryCopyWithImpl;
@useResult
$Res call({
 String package, String? version
});




}
/// @nodoc
class _$InstallSourceRepositoryCopyWithImpl<$Res>
    implements $InstallSourceRepositoryCopyWith<$Res> {
  _$InstallSourceRepositoryCopyWithImpl(this._self, this._then);

  final InstallSourceRepository _self;
  final $Res Function(InstallSourceRepository) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? package = null,Object? version = freezed,}) {
  return _then(InstallSourceRepository(
package: null == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class InstallSourceZip implements InstallSource {
  const InstallSourceZip({required this.bytes, required this.fileName});
  

 final  Uint8List bytes;
 final  String fileName;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceZipCopyWith<InstallSourceZip> get copyWith => _$InstallSourceZipCopyWithImpl<InstallSourceZip>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceZip&&const DeepCollectionEquality().equals(other.bytes, bytes)&&(identical(other.fileName, fileName) || other.fileName == fileName));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes),fileName);

@override
String toString() {
  return 'InstallSource.zip(bytes: $bytes, fileName: $fileName)';
}


}

/// @nodoc
abstract mixin class $InstallSourceZipCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceZipCopyWith(InstallSourceZip value, $Res Function(InstallSourceZip) _then) = _$InstallSourceZipCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes, String fileName
});




}
/// @nodoc
class _$InstallSourceZipCopyWithImpl<$Res>
    implements $InstallSourceZipCopyWith<$Res> {
  _$InstallSourceZipCopyWithImpl(this._self, this._then);

  final InstallSourceZip _self;
  final $Res Function(InstallSourceZip) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,Object? fileName = null,}) {
  return _then(InstallSourceZip(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InstallSourceUrl implements InstallSource {
  const InstallSourceUrl({required this.url});
  

 final  String url;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceUrlCopyWith<InstallSourceUrl> get copyWith => _$InstallSourceUrlCopyWithImpl<InstallSourceUrl>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceUrl&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode => Object.hash(runtimeType,url);

@override
String toString() {
  return 'InstallSource.url(url: $url)';
}


}

/// @nodoc
abstract mixin class $InstallSourceUrlCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceUrlCopyWith(InstallSourceUrl value, $Res Function(InstallSourceUrl) _then) = _$InstallSourceUrlCopyWithImpl;
@useResult
$Res call({
 String url
});




}
/// @nodoc
class _$InstallSourceUrlCopyWithImpl<$Res>
    implements $InstallSourceUrlCopyWith<$Res> {
  _$InstallSourceUrlCopyWithImpl(this._self, this._then);

  final InstallSourceUrl _self;
  final $Res Function(InstallSourceUrl) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(InstallSourceUrl(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InstallSourceGit implements InstallSource {
  const InstallSourceGit({required this.url, this.ref});
  

 final  String url;
 final  String? ref;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceGitCopyWith<InstallSourceGit> get copyWith => _$InstallSourceGitCopyWithImpl<InstallSourceGit>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceGit&&(identical(other.url, url) || other.url == url)&&(identical(other.ref, ref) || other.ref == ref));
}


@override
int get hashCode => Object.hash(runtimeType,url,ref);

@override
String toString() {
  return 'InstallSource.git(url: $url, ref: $ref)';
}


}

/// @nodoc
abstract mixin class $InstallSourceGitCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceGitCopyWith(InstallSourceGit value, $Res Function(InstallSourceGit) _then) = _$InstallSourceGitCopyWithImpl;
@useResult
$Res call({
 String url, String? ref
});




}
/// @nodoc
class _$InstallSourceGitCopyWithImpl<$Res>
    implements $InstallSourceGitCopyWith<$Res> {
  _$InstallSourceGitCopyWithImpl(this._self, this._then);

  final InstallSourceGit _self;
  final $Res Function(InstallSourceGit) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? ref = freezed,}) {
  return _then(InstallSourceGit(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,ref: freezed == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class InstallSourceWasm implements InstallSource {
  const InstallSourceWasm({required this.bytes, required this.fileName});
  

 final  Uint8List bytes;
 final  String fileName;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallSourceWasmCopyWith<InstallSourceWasm> get copyWith => _$InstallSourceWasmCopyWithImpl<InstallSourceWasm>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallSourceWasm&&const DeepCollectionEquality().equals(other.bytes, bytes)&&(identical(other.fileName, fileName) || other.fileName == fileName));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes),fileName);

@override
String toString() {
  return 'InstallSource.wasm(bytes: $bytes, fileName: $fileName)';
}


}

/// @nodoc
abstract mixin class $InstallSourceWasmCopyWith<$Res> implements $InstallSourceCopyWith<$Res> {
  factory $InstallSourceWasmCopyWith(InstallSourceWasm value, $Res Function(InstallSourceWasm) _then) = _$InstallSourceWasmCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes, String fileName
});




}
/// @nodoc
class _$InstallSourceWasmCopyWithImpl<$Res>
    implements $InstallSourceWasmCopyWith<$Res> {
  _$InstallSourceWasmCopyWithImpl(this._self, this._then);

  final InstallSourceWasm _self;
  final $Res Function(InstallSourceWasm) _then;

/// Create a copy of InstallSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,Object? fileName = null,}) {
  return _then(InstallSourceWasm(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
