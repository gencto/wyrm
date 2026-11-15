// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'install_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InstallRequest {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallRequest);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'InstallRequest()';
}


}

/// @nodoc
class $InstallRequestCopyWith<$Res>  {
$InstallRequestCopyWith(InstallRequest _, $Res Function(InstallRequest) __);
}



/// @nodoc


class InstallBuiltIn extends InstallRequest {
  const InstallBuiltIn({required this.id, required this.driver, required this.mode}): super._();
  

 final  String id;
 final  String driver;
 final  LinkMode mode;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallBuiltInCopyWith<InstallBuiltIn> get copyWith => _$InstallBuiltInCopyWithImpl<InstallBuiltIn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallBuiltIn&&(identical(other.id, id) || other.id == id)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.mode, mode) || other.mode == mode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,driver,mode);
}

@override
String toString() {
    return 'InstallRequest.builtIn(id: $id, driver: $driver, mode: $mode)';
}


}

/// @nodoc
abstract mixin class $InstallBuiltInCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallBuiltInCopyWith(InstallBuiltIn value, $Res Function(InstallBuiltIn) _then) = _$InstallBuiltInCopyWithImpl;
@useResult
$Res call({
 String id, String driver, LinkMode mode
});




}
/// @nodoc
class _$InstallBuiltInCopyWithImpl<$Res>
    implements $InstallBuiltInCopyWith<$Res> {
  _$InstallBuiltInCopyWithImpl(this._self, this._then);

  final InstallBuiltIn _self;
  final $Res Function(InstallBuiltIn) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? driver = null,Object? mode = null,}) {
  return _then(InstallBuiltIn(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode,
  ));
}


}

/// @nodoc


class InstallRepository extends InstallRequest {
  const InstallRepository({required this.name, required this.package, required this.accept}): super._();
  

 final  String name;
 final  String package;
 final  bool accept;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallRepositoryCopyWith<InstallRepository> get copyWith => _$InstallRepositoryCopyWithImpl<InstallRepository>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallRepository&&(identical(other.name, name) || other.name == name)&&(identical(other.package, package) || other.package == package)&&(identical(other.accept, accept) || other.accept == accept));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,package,accept);
}

@override
String toString() {
    return 'InstallRequest.repository(name: $name, package: $package, accept: $accept)';
}


}

/// @nodoc
abstract mixin class $InstallRepositoryCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallRepositoryCopyWith(InstallRepository value, $Res Function(InstallRepository) _then) = _$InstallRepositoryCopyWithImpl;
@useResult
$Res call({
 String name, String package, bool accept
});




}
/// @nodoc
class _$InstallRepositoryCopyWithImpl<$Res>
    implements $InstallRepositoryCopyWith<$Res> {
  _$InstallRepositoryCopyWithImpl(this._self, this._then);

  final InstallRepository _self;
  final $Res Function(InstallRepository) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? package = null,Object? accept = null,}) {
  return _then(InstallRepository(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,package: null == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class InstallZip extends InstallRequest {
  const InstallZip({required this.name, required this.zip, required this.accept}): super._();
  

 final  String name;
 final  Uint8List zip;
 final  bool accept;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallZipCopyWith<InstallZip> get copyWith => _$InstallZipCopyWithImpl<InstallZip>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallZip&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.zip, zip)&&(identical(other.accept, accept) || other.accept == accept));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,const DeepCollectionEquality().hash(zip),accept);
}

@override
String toString() {
    return 'InstallRequest.zip(name: $name, zip: $zip, accept: $accept)';
}


}

/// @nodoc
abstract mixin class $InstallZipCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallZipCopyWith(InstallZip value, $Res Function(InstallZip) _then) = _$InstallZipCopyWithImpl;
@useResult
$Res call({
 String name, Uint8List zip, bool accept
});




}
/// @nodoc
class _$InstallZipCopyWithImpl<$Res>
    implements $InstallZipCopyWith<$Res> {
  _$InstallZipCopyWithImpl(this._self, this._then);

  final InstallZip _self;
  final $Res Function(InstallZip) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? zip = null,Object? accept = null,}) {
  return _then(InstallZip(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,zip: null == zip ? _self.zip : zip // ignore: cast_nullable_to_non_nullable
as Uint8List,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class InstallUrl extends InstallRequest {
  const InstallUrl({required this.name, required this.url, required this.accept}): super._();
  

 final  String name;
 final  String url;
 final  bool accept;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallUrlCopyWith<InstallUrl> get copyWith => _$InstallUrlCopyWithImpl<InstallUrl>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallUrl&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.accept, accept) || other.accept == accept));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,url,accept);
}

@override
String toString() {
    return 'InstallRequest.url(name: $name, url: $url, accept: $accept)';
}


}

/// @nodoc
abstract mixin class $InstallUrlCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallUrlCopyWith(InstallUrl value, $Res Function(InstallUrl) _then) = _$InstallUrlCopyWithImpl;
@useResult
$Res call({
 String name, String url, bool accept
});




}
/// @nodoc
class _$InstallUrlCopyWithImpl<$Res>
    implements $InstallUrlCopyWith<$Res> {
  _$InstallUrlCopyWithImpl(this._self, this._then);

  final InstallUrl _self;
  final $Res Function(InstallUrl) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? url = null,Object? accept = null,}) {
  return _then(InstallUrl(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class InstallGit extends InstallRequest {
  const InstallGit({required this.name, required this.url, required this.accept, this.ref}): super._();
  

 final  String name;
 final  String url;
 final  bool accept;
 final  String? ref;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallGitCopyWith<InstallGit> get copyWith => _$InstallGitCopyWithImpl<InstallGit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallGit&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.accept, accept) || other.accept == accept)&&(identical(other.ref, ref) || other.ref == ref));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,url,accept,ref);
}

@override
String toString() {
    return 'InstallRequest.git(name: $name, url: $url, accept: $accept, ref: $ref)';
}


}

/// @nodoc
abstract mixin class $InstallGitCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallGitCopyWith(InstallGit value, $Res Function(InstallGit) _then) = _$InstallGitCopyWithImpl;
@useResult
$Res call({
 String name, String url, bool accept, String? ref
});




}
/// @nodoc
class _$InstallGitCopyWithImpl<$Res>
    implements $InstallGitCopyWith<$Res> {
  _$InstallGitCopyWithImpl(this._self, this._then);

  final InstallGit _self;
  final $Res Function(InstallGit) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? url = null,Object? accept = null,Object? ref = freezed,}) {
  return _then(InstallGit(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,ref: freezed == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class InstallWasm extends InstallRequest {
  const InstallWasm({required this.name, required this.wasm, required this.accept}): super._();
  

 final  String name;
 final  Uint8List wasm;
 final  bool accept;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallWasmCopyWith<InstallWasm> get copyWith => _$InstallWasmCopyWithImpl<InstallWasm>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallWasm&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.wasm, wasm)&&(identical(other.accept, accept) || other.accept == accept));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,const DeepCollectionEquality().hash(wasm),accept);
}

@override
String toString() {
    return 'InstallRequest.wasm(name: $name, wasm: $wasm, accept: $accept)';
}


}

/// @nodoc
abstract mixin class $InstallWasmCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallWasmCopyWith(InstallWasm value, $Res Function(InstallWasm) _then) = _$InstallWasmCopyWithImpl;
@useResult
$Res call({
 String name, Uint8List wasm, bool accept
});




}
/// @nodoc
class _$InstallWasmCopyWithImpl<$Res>
    implements $InstallWasmCopyWith<$Res> {
  _$InstallWasmCopyWithImpl(this._self, this._then);

  final InstallWasm _self;
  final $Res Function(InstallWasm) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? wasm = null,Object? accept = null,}) {
  return _then(InstallWasm(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,wasm: null == wasm ? _self.wasm : wasm // ignore: cast_nullable_to_non_nullable
as Uint8List,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class InstallBackup extends InstallRequest {
  const InstallBackup({required this.upload, required this.id, required this.accept, this.passphrase}): super._();
  

 final  String upload;
 final  String id;
 final  bool accept;
 final  String? passphrase;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallBackupCopyWith<InstallBackup> get copyWith => _$InstallBackupCopyWithImpl<InstallBackup>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallBackup&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.id, id) || other.id == id)&&(identical(other.accept, accept) || other.accept == accept)&&(identical(other.passphrase, passphrase) || other.passphrase == passphrase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,upload,id,accept,passphrase);
}

@override
String toString() {
    return 'InstallRequest.backup(upload: $upload, id: $id, accept: $accept, passphrase: $passphrase)';
}


}

/// @nodoc
abstract mixin class $InstallBackupCopyWith<$Res> implements $InstallRequestCopyWith<$Res> {
  factory $InstallBackupCopyWith(InstallBackup value, $Res Function(InstallBackup) _then) = _$InstallBackupCopyWithImpl;
@useResult
$Res call({
 String upload, String id, bool accept, String? passphrase
});




}
/// @nodoc
class _$InstallBackupCopyWithImpl<$Res>
    implements $InstallBackupCopyWith<$Res> {
  _$InstallBackupCopyWithImpl(this._self, this._then);

  final InstallBackup _self;
  final $Res Function(InstallBackup) _then;

/// Create a copy of InstallRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? upload = null,Object? id = null,Object? accept = null,Object? passphrase = freezed,}) {
  return _then(InstallBackup(
upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,accept: null == accept ? _self.accept : accept // ignore: cast_nullable_to_non_nullable
as bool,passphrase: freezed == passphrase ? _self.passphrase : passphrase // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
