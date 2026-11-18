// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_finding.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageFinding {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageFinding);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding()';
}


}

/// @nodoc
class $PackageFindingCopyWith<$Res>  {
$PackageFindingCopyWith(PackageFinding _, $Res Function(PackageFinding) __);
}



/// @nodoc


class FindingTooLarge implements PackageFinding {
  const FindingTooLarge({required this.mib, required this.limitMib, required this.zipped});
  

 final  int mib;
 final  int limitMib;
 final  bool zipped;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingTooLargeCopyWith<FindingTooLarge> get copyWith => _$FindingTooLargeCopyWithImpl<FindingTooLarge>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingTooLarge&&(identical(other.mib, mib) || other.mib == mib)&&(identical(other.limitMib, limitMib) || other.limitMib == limitMib)&&(identical(other.zipped, zipped) || other.zipped == zipped));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mib,limitMib,zipped);
}

@override
String toString() {
    return 'PackageFinding.tooLarge(mib: $mib, limitMib: $limitMib, zipped: $zipped)';
}


}

/// @nodoc
abstract mixin class $FindingTooLargeCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingTooLargeCopyWith(FindingTooLarge value, $Res Function(FindingTooLarge) _then) = _$FindingTooLargeCopyWithImpl;
@useResult
$Res call({
 int mib, int limitMib, bool zipped
});




}
/// @nodoc
class _$FindingTooLargeCopyWithImpl<$Res>
    implements $FindingTooLargeCopyWith<$Res> {
  _$FindingTooLargeCopyWithImpl(this._self, this._then);

  final FindingTooLarge _self;
  final $Res Function(FindingTooLarge) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mib = null,Object? limitMib = null,Object? zipped = null,}) {
  return _then(FindingTooLarge(
mib: null == mib ? _self.mib : mib // ignore: cast_nullable_to_non_nullable
as int,limitMib: null == limitMib ? _self.limitMib : limitMib // ignore: cast_nullable_to_non_nullable
as int,zipped: null == zipped ? _self.zipped : zipped // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingNotZip implements PackageFinding {
  const FindingNotZip({this.error});
  

 final  String? error;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingNotZipCopyWith<FindingNotZip> get copyWith => _$FindingNotZipCopyWithImpl<FindingNotZip>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingNotZip&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'PackageFinding.notZip(error: $error)';
}


}

/// @nodoc
abstract mixin class $FindingNotZipCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingNotZipCopyWith(FindingNotZip value, $Res Function(FindingNotZip) _then) = _$FindingNotZipCopyWithImpl;
@useResult
$Res call({
 String? error
});




}
/// @nodoc
class _$FindingNotZipCopyWithImpl<$Res>
    implements $FindingNotZipCopyWith<$Res> {
  _$FindingNotZipCopyWithImpl(this._self, this._then);

  final FindingNotZip _self;
  final $Res Function(FindingNotZip) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = freezed,}) {
  return _then(FindingNotZip(
error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class FindingTooManyFiles implements PackageFinding {
  const FindingTooManyFiles({required this.files, required this.mib, required this.maxFiles, required this.maxMib});
  

 final  int files;
 final  int mib;
 final  int maxFiles;
 final  int maxMib;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingTooManyFilesCopyWith<FindingTooManyFiles> get copyWith => _$FindingTooManyFilesCopyWithImpl<FindingTooManyFiles>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingTooManyFiles&&(identical(other.files, files) || other.files == files)&&(identical(other.mib, mib) || other.mib == mib)&&(identical(other.maxFiles, maxFiles) || other.maxFiles == maxFiles)&&(identical(other.maxMib, maxMib) || other.maxMib == maxMib));
}


@override
int get hashCode {
    return Object.hash(runtimeType,files,mib,maxFiles,maxMib);
}

@override
String toString() {
    return 'PackageFinding.tooManyFiles(files: $files, mib: $mib, maxFiles: $maxFiles, maxMib: $maxMib)';
}


}

/// @nodoc
abstract mixin class $FindingTooManyFilesCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingTooManyFilesCopyWith(FindingTooManyFiles value, $Res Function(FindingTooManyFiles) _then) = _$FindingTooManyFilesCopyWithImpl;
@useResult
$Res call({
 int files, int mib, int maxFiles, int maxMib
});




}
/// @nodoc
class _$FindingTooManyFilesCopyWithImpl<$Res>
    implements $FindingTooManyFilesCopyWith<$Res> {
  _$FindingTooManyFilesCopyWithImpl(this._self, this._then);

  final FindingTooManyFiles _self;
  final $Res Function(FindingTooManyFiles) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? files = null,Object? mib = null,Object? maxFiles = null,Object? maxMib = null,}) {
  return _then(FindingTooManyFiles(
files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int,mib: null == mib ? _self.mib : mib // ignore: cast_nullable_to_non_nullable
as int,maxFiles: null == maxFiles ? _self.maxFiles : maxFiles // ignore: cast_nullable_to_non_nullable
as int,maxMib: null == maxMib ? _self.maxMib : maxMib // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FindingSizeAndFiles implements PackageFinding {
  const FindingSizeAndFiles({required this.kib, required this.files});
  

 final  int kib;
 final  int files;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingSizeAndFilesCopyWith<FindingSizeAndFiles> get copyWith => _$FindingSizeAndFilesCopyWithImpl<FindingSizeAndFiles>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingSizeAndFiles&&(identical(other.kib, kib) || other.kib == kib)&&(identical(other.files, files) || other.files == files));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kib,files);
}

@override
String toString() {
    return 'PackageFinding.sizeAndFiles(kib: $kib, files: $files)';
}


}

/// @nodoc
abstract mixin class $FindingSizeAndFilesCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingSizeAndFilesCopyWith(FindingSizeAndFiles value, $Res Function(FindingSizeAndFiles) _then) = _$FindingSizeAndFilesCopyWithImpl;
@useResult
$Res call({
 int kib, int files
});




}
/// @nodoc
class _$FindingSizeAndFilesCopyWithImpl<$Res>
    implements $FindingSizeAndFilesCopyWith<$Res> {
  _$FindingSizeAndFilesCopyWithImpl(this._self, this._then);

  final FindingSizeAndFiles _self;
  final $Res Function(FindingSizeAndFiles) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kib = null,Object? files = null,}) {
  return _then(FindingSizeAndFiles(
kib: null == kib ? _self.kib : kib // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FindingSize implements PackageFinding {
  const FindingSize({required this.kib});
  

 final  int kib;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingSizeCopyWith<FindingSize> get copyWith => _$FindingSizeCopyWithImpl<FindingSize>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingSize&&(identical(other.kib, kib) || other.kib == kib));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kib);
}

@override
String toString() {
    return 'PackageFinding.size(kib: $kib)';
}


}

/// @nodoc
abstract mixin class $FindingSizeCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingSizeCopyWith(FindingSize value, $Res Function(FindingSize) _then) = _$FindingSizeCopyWithImpl;
@useResult
$Res call({
 int kib
});




}
/// @nodoc
class _$FindingSizeCopyWithImpl<$Res>
    implements $FindingSizeCopyWith<$Res> {
  _$FindingSizeCopyWithImpl(this._self, this._then);

  final FindingSize _self;
  final $Res Function(FindingSize) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kib = null,}) {
  return _then(FindingSize(
kib: null == kib ? _self.kib : kib // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FindingArchiveEntries implements PackageFinding {
  const FindingArchiveEntries(this.count);
  

 final  int count;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingArchiveEntriesCopyWith<FindingArchiveEntries> get copyWith => _$FindingArchiveEntriesCopyWithImpl<FindingArchiveEntries>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingArchiveEntries&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode {
    return Object.hash(runtimeType,count);
}

@override
String toString() {
    return 'PackageFinding.archiveEntries(count: $count)';
}


}

/// @nodoc
abstract mixin class $FindingArchiveEntriesCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingArchiveEntriesCopyWith(FindingArchiveEntries value, $Res Function(FindingArchiveEntries) _then) = _$FindingArchiveEntriesCopyWithImpl;
@useResult
$Res call({
 int count
});




}
/// @nodoc
class _$FindingArchiveEntriesCopyWithImpl<$Res>
    implements $FindingArchiveEntriesCopyWith<$Res> {
  _$FindingArchiveEntriesCopyWithImpl(this._self, this._then);

  final FindingArchiveEntries _self;
  final $Res Function(FindingArchiveEntries) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? count = null,}) {
  return _then(FindingArchiveEntries(
null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FindingPathNotRelative implements PackageFinding {
  const FindingPathNotRelative(this.path);
  

 final  String path;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingPathNotRelativeCopyWith<FindingPathNotRelative> get copyWith => _$FindingPathNotRelativeCopyWithImpl<FindingPathNotRelative>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingPathNotRelative&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}

@override
String toString() {
    return 'PackageFinding.pathNotRelative(path: $path)';
}


}

/// @nodoc
abstract mixin class $FindingPathNotRelativeCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingPathNotRelativeCopyWith(FindingPathNotRelative value, $Res Function(FindingPathNotRelative) _then) = _$FindingPathNotRelativeCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$FindingPathNotRelativeCopyWithImpl<$Res>
    implements $FindingPathNotRelativeCopyWith<$Res> {
  _$FindingPathNotRelativeCopyWithImpl(this._self, this._then);

  final FindingPathNotRelative _self;
  final $Res Function(FindingPathNotRelative) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(FindingPathNotRelative(
null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingSymbolicLink implements PackageFinding {
  const FindingSymbolicLink(this.name);
  

 final  String name;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingSymbolicLinkCopyWith<FindingSymbolicLink> get copyWith => _$FindingSymbolicLinkCopyWithImpl<FindingSymbolicLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingSymbolicLink&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'PackageFinding.symbolicLink(name: $name)';
}


}

/// @nodoc
abstract mixin class $FindingSymbolicLinkCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingSymbolicLinkCopyWith(FindingSymbolicLink value, $Res Function(FindingSymbolicLink) _then) = _$FindingSymbolicLinkCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$FindingSymbolicLinkCopyWithImpl<$Res>
    implements $FindingSymbolicLinkCopyWith<$Res> {
  _$FindingSymbolicLinkCopyWithImpl(this._self, this._then);

  final FindingSymbolicLink _self;
  final $Res Function(FindingSymbolicLink) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(FindingSymbolicLink(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingPathsOk implements PackageFinding {
  const FindingPathsOk();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingPathsOk);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding.pathsOk()';
}


}




/// @nodoc


class FindingNoManifest implements PackageFinding {
  const FindingNoManifest(this.file);
  

 final  String file;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingNoManifestCopyWith<FindingNoManifest> get copyWith => _$FindingNoManifestCopyWithImpl<FindingNoManifest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingNoManifest&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode {
    return Object.hash(runtimeType,file);
}

@override
String toString() {
    return 'PackageFinding.noManifest(file: $file)';
}


}

/// @nodoc
abstract mixin class $FindingNoManifestCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingNoManifestCopyWith(FindingNoManifest value, $Res Function(FindingNoManifest) _then) = _$FindingNoManifestCopyWithImpl;
@useResult
$Res call({
 String file
});




}
/// @nodoc
class _$FindingNoManifestCopyWithImpl<$Res>
    implements $FindingNoManifestCopyWith<$Res> {
  _$FindingNoManifestCopyWithImpl(this._self, this._then);

  final FindingNoManifest _self;
  final $Res Function(FindingNoManifest) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? file = null,}) {
  return _then(FindingNoManifest(
null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingManifestProblem implements PackageFinding {
  const FindingManifestProblem(this.problem, this.file);
  

 final  ManifestProblem problem;
 final  String file;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingManifestProblemCopyWith<FindingManifestProblem> get copyWith => _$FindingManifestProblemCopyWithImpl<FindingManifestProblem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingManifestProblem&&(identical(other.problem, problem) || other.problem == problem)&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode {
    return Object.hash(runtimeType,problem,file);
}

@override
String toString() {
    return 'PackageFinding.manifestProblem(problem: $problem, file: $file)';
}


}

/// @nodoc
abstract mixin class $FindingManifestProblemCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingManifestProblemCopyWith(FindingManifestProblem value, $Res Function(FindingManifestProblem) _then) = _$FindingManifestProblemCopyWithImpl;
@useResult
$Res call({
 ManifestProblem problem, String file
});


$ManifestProblemCopyWith<$Res> get problem;

}
/// @nodoc
class _$FindingManifestProblemCopyWithImpl<$Res>
    implements $FindingManifestProblemCopyWith<$Res> {
  _$FindingManifestProblemCopyWithImpl(this._self, this._then);

  final FindingManifestProblem _self;
  final $Res Function(FindingManifestProblem) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problem = null,Object? file = null,}) {
  return _then(FindingManifestProblem(
null == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem,null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res> get problem {
  
  return $ManifestProblemCopyWith<$Res>(_self.problem, (value) {
    return _then(_self.copyWith(problem: value));
  });
}
}

/// @nodoc


class FindingUnknownFields implements PackageFinding {
  const FindingUnknownFields(this.fields);
  

 final  IList<String> fields;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingUnknownFieldsCopyWith<FindingUnknownFields> get copyWith => _$FindingUnknownFieldsCopyWithImpl<FindingUnknownFields>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingUnknownFields&&const DeepCollectionEquality().equals(other.fields, fields));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(fields));
}

@override
String toString() {
    return 'PackageFinding.unknownFields(fields: $fields)';
}


}

/// @nodoc
abstract mixin class $FindingUnknownFieldsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingUnknownFieldsCopyWith(FindingUnknownFields value, $Res Function(FindingUnknownFields) _then) = _$FindingUnknownFieldsCopyWithImpl;
@useResult
$Res call({
 IList<String> fields
});




}
/// @nodoc
class _$FindingUnknownFieldsCopyWithImpl<$Res>
    implements $FindingUnknownFieldsCopyWith<$Res> {
  _$FindingUnknownFieldsCopyWithImpl(this._self, this._then);

  final FindingUnknownFields _self;
  final $Res Function(FindingUnknownFields) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fields = null,}) {
  return _then(FindingUnknownFields(
null == fields ? _self.fields : fields // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

/// @nodoc


class FindingMissingFields implements PackageFinding {
  const FindingMissingFields(this.fields);
  

 final  IList<String> fields;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingMissingFieldsCopyWith<FindingMissingFields> get copyWith => _$FindingMissingFieldsCopyWithImpl<FindingMissingFields>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingMissingFields&&const DeepCollectionEquality().equals(other.fields, fields));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(fields));
}

@override
String toString() {
    return 'PackageFinding.missingFields(fields: $fields)';
}


}

/// @nodoc
abstract mixin class $FindingMissingFieldsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingMissingFieldsCopyWith(FindingMissingFields value, $Res Function(FindingMissingFields) _then) = _$FindingMissingFieldsCopyWithImpl;
@useResult
$Res call({
 IList<String> fields
});




}
/// @nodoc
class _$FindingMissingFieldsCopyWithImpl<$Res>
    implements $FindingMissingFieldsCopyWith<$Res> {
  _$FindingMissingFieldsCopyWithImpl(this._self, this._then);

  final FindingMissingFields _self;
  final $Res Function(FindingMissingFields) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fields = null,}) {
  return _then(FindingMissingFields(
null == fields ? _self.fields : fields // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

/// @nodoc


class FindingManifestOk implements PackageFinding {
  const FindingManifestOk(this.file);
  

 final  String file;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingManifestOkCopyWith<FindingManifestOk> get copyWith => _$FindingManifestOkCopyWithImpl<FindingManifestOk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingManifestOk&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode {
    return Object.hash(runtimeType,file);
}

@override
String toString() {
    return 'PackageFinding.manifestOk(file: $file)';
}


}

/// @nodoc
abstract mixin class $FindingManifestOkCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingManifestOkCopyWith(FindingManifestOk value, $Res Function(FindingManifestOk) _then) = _$FindingManifestOkCopyWithImpl;
@useResult
$Res call({
 String file
});




}
/// @nodoc
class _$FindingManifestOkCopyWithImpl<$Res>
    implements $FindingManifestOkCopyWith<$Res> {
  _$FindingManifestOkCopyWithImpl(this._self, this._then);

  final FindingManifestOk _self;
  final $Res Function(FindingManifestOk) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? file = null,}) {
  return _then(FindingManifestOk(
null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingProtocol implements PackageFinding {
  const FindingProtocol({required this.found, required this.speak, required this.matches});
  

 final  String? found;
 final  int speak;
 final  bool matches;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingProtocolCopyWith<FindingProtocol> get copyWith => _$FindingProtocolCopyWithImpl<FindingProtocol>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingProtocol&&(identical(other.found, found) || other.found == found)&&(identical(other.speak, speak) || other.speak == speak)&&(identical(other.matches, matches) || other.matches == matches));
}


@override
int get hashCode {
    return Object.hash(runtimeType,found,speak,matches);
}

@override
String toString() {
    return 'PackageFinding.protocol(found: $found, speak: $speak, matches: $matches)';
}


}

/// @nodoc
abstract mixin class $FindingProtocolCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingProtocolCopyWith(FindingProtocol value, $Res Function(FindingProtocol) _then) = _$FindingProtocolCopyWithImpl;
@useResult
$Res call({
 String? found, int speak, bool matches
});




}
/// @nodoc
class _$FindingProtocolCopyWithImpl<$Res>
    implements $FindingProtocolCopyWith<$Res> {
  _$FindingProtocolCopyWithImpl(this._self, this._then);

  final FindingProtocol _self;
  final $Res Function(FindingProtocol) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? found = freezed,Object? speak = null,Object? matches = null,}) {
  return _then(FindingProtocol(
found: freezed == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as String?,speak: null == speak ? _self.speak : speak // ignore: cast_nullable_to_non_nullable
as int,matches: null == matches ? _self.matches : matches // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingNameVersion implements PackageFinding {
  const FindingNameVersion({required this.name, required this.version, required this.ok});
  

 final  String name;
 final  String? version;
 final  bool ok;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingNameVersionCopyWith<FindingNameVersion> get copyWith => _$FindingNameVersionCopyWithImpl<FindingNameVersion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingNameVersion&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.ok, ok) || other.ok == ok));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,version,ok);
}

@override
String toString() {
    return 'PackageFinding.nameVersion(name: $name, version: $version, ok: $ok)';
}


}

/// @nodoc
abstract mixin class $FindingNameVersionCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingNameVersionCopyWith(FindingNameVersion value, $Res Function(FindingNameVersion) _then) = _$FindingNameVersionCopyWithImpl;
@useResult
$Res call({
 String name, String? version, bool ok
});




}
/// @nodoc
class _$FindingNameVersionCopyWithImpl<$Res>
    implements $FindingNameVersionCopyWith<$Res> {
  _$FindingNameVersionCopyWithImpl(this._self, this._then);

  final FindingNameVersion _self;
  final $Res Function(FindingNameVersion) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = freezed,Object? ok = null,}) {
  return _then(FindingNameVersion(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingEntryMissing implements PackageFinding {
  const FindingEntryMissing(this.hosts);
  

 final  IList<String> hosts;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingEntryMissingCopyWith<FindingEntryMissing> get copyWith => _$FindingEntryMissingCopyWithImpl<FindingEntryMissing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingEntryMissing&&const DeepCollectionEquality().equals(other.hosts, hosts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(hosts));
}

@override
String toString() {
    return 'PackageFinding.entryMissing(hosts: $hosts)';
}


}

/// @nodoc
abstract mixin class $FindingEntryMissingCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingEntryMissingCopyWith(FindingEntryMissing value, $Res Function(FindingEntryMissing) _then) = _$FindingEntryMissingCopyWithImpl;
@useResult
$Res call({
 IList<String> hosts
});




}
/// @nodoc
class _$FindingEntryMissingCopyWithImpl<$Res>
    implements $FindingEntryMissingCopyWith<$Res> {
  _$FindingEntryMissingCopyWithImpl(this._self, this._then);

  final FindingEntryMissing _self;
  final $Res Function(FindingEntryMissing) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hosts = null,}) {
  return _then(FindingEntryMissing(
null == hosts ? _self.hosts : hosts // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

/// @nodoc


class FindingHosts implements PackageFinding {
  const FindingHosts(this.hosts);
  

 final  IList<String> hosts;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingHostsCopyWith<FindingHosts> get copyWith => _$FindingHostsCopyWithImpl<FindingHosts>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingHosts&&const DeepCollectionEquality().equals(other.hosts, hosts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(hosts));
}

@override
String toString() {
    return 'PackageFinding.hosts(hosts: $hosts)';
}


}

/// @nodoc
abstract mixin class $FindingHostsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingHostsCopyWith(FindingHosts value, $Res Function(FindingHosts) _then) = _$FindingHostsCopyWithImpl;
@useResult
$Res call({
 IList<String> hosts
});




}
/// @nodoc
class _$FindingHostsCopyWithImpl<$Res>
    implements $FindingHostsCopyWith<$Res> {
  _$FindingHostsCopyWithImpl(this._self, this._then);

  final FindingHosts _self;
  final $Res Function(FindingHosts) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hosts = null,}) {
  return _then(FindingHosts(
null == hosts ? _self.hosts : hosts // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

/// @nodoc


class FindingNeedsEntries implements PackageFinding {
  const FindingNeedsEntries();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingNeedsEntries);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding.needsEntries()';
}


}




/// @nodoc


class FindingHost implements PackageFinding {
  const FindingHost(this.host, {required this.present});
  

 final  String host;
 final  bool present;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingHostCopyWith<FindingHost> get copyWith => _$FindingHostCopyWithImpl<FindingHost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingHost&&(identical(other.host, host) || other.host == host)&&(identical(other.present, present) || other.present == present));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,present);
}

@override
String toString() {
    return 'PackageFinding.host(host: $host, present: $present)';
}


}

/// @nodoc
abstract mixin class $FindingHostCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingHostCopyWith(FindingHost value, $Res Function(FindingHost) _then) = _$FindingHostCopyWithImpl;
@useResult
$Res call({
 String host, bool present
});




}
/// @nodoc
class _$FindingHostCopyWithImpl<$Res>
    implements $FindingHostCopyWith<$Res> {
  _$FindingHostCopyWithImpl(this._self, this._then);

  final FindingHost _self;
  final $Res Function(FindingHost) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? present = null,}) {
  return _then(FindingHost(
null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,present: null == present ? _self.present : present // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingComponent implements PackageFinding {
  const FindingComponent({required this.entry, required this.found, required this.wasm});
  

 final  String? entry;
 final  bool found;
 final  bool wasm;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingComponentCopyWith<FindingComponent> get copyWith => _$FindingComponentCopyWithImpl<FindingComponent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingComponent&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.found, found) || other.found == found)&&(identical(other.wasm, wasm) || other.wasm == wasm));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,found,wasm);
}

@override
String toString() {
    return 'PackageFinding.component(entry: $entry, found: $found, wasm: $wasm)';
}


}

/// @nodoc
abstract mixin class $FindingComponentCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingComponentCopyWith(FindingComponent value, $Res Function(FindingComponent) _then) = _$FindingComponentCopyWithImpl;
@useResult
$Res call({
 String? entry, bool found, bool wasm
});




}
/// @nodoc
class _$FindingComponentCopyWithImpl<$Res>
    implements $FindingComponentCopyWith<$Res> {
  _$FindingComponentCopyWithImpl(this._self, this._then);

  final FindingComponent _self;
  final $Res Function(FindingComponent) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entry = freezed,Object? found = null,Object? wasm = null,}) {
  return _then(FindingComponent(
entry: freezed == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String?,found: null == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as bool,wasm: null == wasm ? _self.wasm : wasm // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingWorldByBroker implements PackageFinding {
  const FindingWorldByBroker();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingWorldByBroker);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding.worldByBroker()';
}


}




/// @nodoc


class FindingRights implements PackageFinding {
  const FindingRights(this.rights);
  

 final  IList<RequestedRight> rights;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingRightsCopyWith<FindingRights> get copyWith => _$FindingRightsCopyWithImpl<FindingRights>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingRights&&const DeepCollectionEquality().equals(other.rights, rights));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(rights));
}

@override
String toString() {
    return 'PackageFinding.rights(rights: $rights)';
}


}

/// @nodoc
abstract mixin class $FindingRightsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingRightsCopyWith(FindingRights value, $Res Function(FindingRights) _then) = _$FindingRightsCopyWithImpl;
@useResult
$Res call({
 IList<RequestedRight> rights
});




}
/// @nodoc
class _$FindingRightsCopyWithImpl<$Res>
    implements $FindingRightsCopyWith<$Res> {
  _$FindingRightsCopyWithImpl(this._self, this._then);

  final FindingRights _self;
  final $Res Function(FindingRights) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rights = null,}) {
  return _then(FindingRights(
null == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>,
  ));
}


}

/// @nodoc


class FindingRightsProblem implements PackageFinding {
  const FindingRightsProblem(this.problem, this.file);
  

 final  ManifestProblem problem;
 final  String file;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingRightsProblemCopyWith<FindingRightsProblem> get copyWith => _$FindingRightsProblemCopyWithImpl<FindingRightsProblem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingRightsProblem&&(identical(other.problem, problem) || other.problem == problem)&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode {
    return Object.hash(runtimeType,problem,file);
}

@override
String toString() {
    return 'PackageFinding.rightsProblem(problem: $problem, file: $file)';
}


}

/// @nodoc
abstract mixin class $FindingRightsProblemCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingRightsProblemCopyWith(FindingRightsProblem value, $Res Function(FindingRightsProblem) _then) = _$FindingRightsProblemCopyWithImpl;
@useResult
$Res call({
 ManifestProblem problem, String file
});


$ManifestProblemCopyWith<$Res> get problem;

}
/// @nodoc
class _$FindingRightsProblemCopyWithImpl<$Res>
    implements $FindingRightsProblemCopyWith<$Res> {
  _$FindingRightsProblemCopyWithImpl(this._self, this._then);

  final FindingRightsProblem _self;
  final $Res Function(FindingRightsProblem) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problem = null,Object? file = null,}) {
  return _then(FindingRightsProblem(
null == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem,null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res> get problem {
  
  return $ManifestProblemCopyWith<$Res>(_self.problem, (value) {
    return _then(_self.copyWith(problem: value));
  });
}
}

/// @nodoc


class FindingOtherKind implements PackageFinding {
  const FindingOtherKind(this.kind);
  

 final  String kind;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingOtherKindCopyWith<FindingOtherKind> get copyWith => _$FindingOtherKindCopyWithImpl<FindingOtherKind>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingOtherKind&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind);
}

@override
String toString() {
    return 'PackageFinding.otherKind(kind: $kind)';
}


}

/// @nodoc
abstract mixin class $FindingOtherKindCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingOtherKindCopyWith(FindingOtherKind value, $Res Function(FindingOtherKind) _then) = _$FindingOtherKindCopyWithImpl;
@useResult
$Res call({
 String kind
});




}
/// @nodoc
class _$FindingOtherKindCopyWithImpl<$Res>
    implements $FindingOtherKindCopyWith<$Res> {
  _$FindingOtherKindCopyWithImpl(this._self, this._then);

  final FindingOtherKind _self;
  final $Res Function(FindingOtherKind) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,}) {
  return _then(FindingOtherKind(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingLink implements PackageFinding {
  const FindingLink(this.link);
  

 final  BackupLinkFacts link;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingLinkCopyWith<FindingLink> get copyWith => _$FindingLinkCopyWithImpl<FindingLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingLink&&(identical(other.link, link) || other.link == link));
}


@override
int get hashCode {
    return Object.hash(runtimeType,link);
}

@override
String toString() {
    return 'PackageFinding.link(link: $link)';
}


}

/// @nodoc
abstract mixin class $FindingLinkCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingLinkCopyWith(FindingLink value, $Res Function(FindingLink) _then) = _$FindingLinkCopyWithImpl;
@useResult
$Res call({
 BackupLinkFacts link
});


$BackupLinkFactsCopyWith<$Res> get link;

}
/// @nodoc
class _$FindingLinkCopyWithImpl<$Res>
    implements $FindingLinkCopyWith<$Res> {
  _$FindingLinkCopyWithImpl(this._self, this._then);

  final FindingLink _self;
  final $Res Function(FindingLink) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? link = null,}) {
  return _then(FindingLink(
null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as BackupLinkFacts,
  ));
}

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackupLinkFactsCopyWith<$Res> get link {
  
  return $BackupLinkFactsCopyWith<$Res>(_self.link, (value) {
    return _then(_self.copyWith(link: value));
  });
}
}

/// @nodoc


class FindingPackageOfLink implements PackageFinding {
  const FindingPackageOfLink({required this.name, required this.version, required this.inFile});
  

 final  String name;
 final  String version;
 final  bool inFile;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingPackageOfLinkCopyWith<FindingPackageOfLink> get copyWith => _$FindingPackageOfLinkCopyWithImpl<FindingPackageOfLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingPackageOfLink&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.inFile, inFile) || other.inFile == inFile));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,version,inFile);
}

@override
String toString() {
    return 'PackageFinding.packageOfLink(name: $name, version: $version, inFile: $inFile)';
}


}

/// @nodoc
abstract mixin class $FindingPackageOfLinkCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingPackageOfLinkCopyWith(FindingPackageOfLink value, $Res Function(FindingPackageOfLink) _then) = _$FindingPackageOfLinkCopyWithImpl;
@useResult
$Res call({
 String name, String version, bool inFile
});




}
/// @nodoc
class _$FindingPackageOfLinkCopyWithImpl<$Res>
    implements $FindingPackageOfLinkCopyWith<$Res> {
  _$FindingPackageOfLinkCopyWithImpl(this._self, this._then);

  final FindingPackageOfLink _self;
  final $Res Function(FindingPackageOfLink) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = null,Object? inFile = null,}) {
  return _then(FindingPackageOfLink(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,inFile: null == inFile ? _self.inFile : inFile // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FindingSecrets implements PackageFinding {
  const FindingSecrets(this.sealed, this.site);
  

 final  BackupSealed sealed;
 final  String site;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingSecretsCopyWith<FindingSecrets> get copyWith => _$FindingSecretsCopyWithImpl<FindingSecrets>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingSecrets&&(identical(other.sealed, sealed) || other.sealed == sealed)&&(identical(other.site, site) || other.site == site));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sealed,site);
}

@override
String toString() {
    return 'PackageFinding.secrets(sealed: $sealed, site: $site)';
}


}

/// @nodoc
abstract mixin class $FindingSecretsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingSecretsCopyWith(FindingSecrets value, $Res Function(FindingSecrets) _then) = _$FindingSecretsCopyWithImpl;
@useResult
$Res call({
 BackupSealed sealed, String site
});




}
/// @nodoc
class _$FindingSecretsCopyWithImpl<$Res>
    implements $FindingSecretsCopyWith<$Res> {
  _$FindingSecretsCopyWithImpl(this._self, this._then);

  final FindingSecrets _self;
  final $Res Function(FindingSecrets) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sealed = null,Object? site = null,}) {
  return _then(FindingSecrets(
null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as BackupSealed,null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FindingSections implements PackageFinding {
  const FindingSections(this.sections);
  

 final  IList<BackupSection> sections;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingSectionsCopyWith<FindingSections> get copyWith => _$FindingSectionsCopyWithImpl<FindingSections>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingSections&&const DeepCollectionEquality().equals(other.sections, sections));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(sections));
}

@override
String toString() {
    return 'PackageFinding.sections(sections: $sections)';
}


}

/// @nodoc
abstract mixin class $FindingSectionsCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingSectionsCopyWith(FindingSections value, $Res Function(FindingSections) _then) = _$FindingSectionsCopyWithImpl;
@useResult
$Res call({
 IList<BackupSection> sections
});




}
/// @nodoc
class _$FindingSectionsCopyWithImpl<$Res>
    implements $FindingSectionsCopyWith<$Res> {
  _$FindingSectionsCopyWithImpl(this._self, this._then);

  final FindingSections _self;
  final $Res Function(FindingSections) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sections = null,}) {
  return _then(FindingSections(
null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,
  ));
}


}

/// @nodoc


class FindingCheckedAsNewLink implements PackageFinding {
  const FindingCheckedAsNewLink();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingCheckedAsNewLink);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding.checkedAsNewLink()';
}


}




/// @nodoc


class FindingNotReadHere implements PackageFinding {
  const FindingNotReadHere({required this.mib});
  

 final  int mib;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingNotReadHereCopyWith<FindingNotReadHere> get copyWith => _$FindingNotReadHereCopyWithImpl<FindingNotReadHere>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingNotReadHere&&(identical(other.mib, mib) || other.mib == mib));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mib);
}

@override
String toString() {
    return 'PackageFinding.notReadHere(mib: $mib)';
}


}

/// @nodoc
abstract mixin class $FindingNotReadHereCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingNotReadHereCopyWith(FindingNotReadHere value, $Res Function(FindingNotReadHere) _then) = _$FindingNotReadHereCopyWithImpl;
@useResult
$Res call({
 int mib
});




}
/// @nodoc
class _$FindingNotReadHereCopyWithImpl<$Res>
    implements $FindingNotReadHereCopyWith<$Res> {
  _$FindingNotReadHereCopyWithImpl(this._self, this._then);

  final FindingNotReadHere _self;
  final $Res Function(FindingNotReadHere) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mib = null,}) {
  return _then(FindingNotReadHere(
mib: null == mib ? _self.mib : mib // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FindingFetchedByBroker implements PackageFinding {
  const FindingFetchedByBroker(this.what);
  

 final  String? what;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FindingFetchedByBrokerCopyWith<FindingFetchedByBroker> get copyWith => _$FindingFetchedByBrokerCopyWithImpl<FindingFetchedByBroker>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingFetchedByBroker&&(identical(other.what, what) || other.what == what));
}


@override
int get hashCode {
    return Object.hash(runtimeType,what);
}

@override
String toString() {
    return 'PackageFinding.fetchedByBroker(what: $what)';
}


}

/// @nodoc
abstract mixin class $FindingFetchedByBrokerCopyWith<$Res> implements $PackageFindingCopyWith<$Res> {
  factory $FindingFetchedByBrokerCopyWith(FindingFetchedByBroker value, $Res Function(FindingFetchedByBroker) _then) = _$FindingFetchedByBrokerCopyWithImpl;
@useResult
$Res call({
 String? what
});




}
/// @nodoc
class _$FindingFetchedByBrokerCopyWithImpl<$Res>
    implements $FindingFetchedByBrokerCopyWith<$Res> {
  _$FindingFetchedByBrokerCopyWithImpl(this._self, this._then);

  final FindingFetchedByBroker _self;
  final $Res Function(FindingFetchedByBroker) _then;

/// Create a copy of PackageFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? what = freezed,}) {
  return _then(FindingFetchedByBroker(
freezed == what ? _self.what : what // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class FindingCheckedAfterDownload implements PackageFinding {
  const FindingCheckedAfterDownload();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FindingCheckedAfterDownload);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageFinding.checkedAfterDownload()';
}


}




// dart format on
