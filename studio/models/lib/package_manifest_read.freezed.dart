// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_manifest_read.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageManifestRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageManifestRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PackageManifestRead()';
}


}

/// @nodoc
class $PackageManifestReadCopyWith<$Res>  {
$PackageManifestReadCopyWith(PackageManifestRead _, $Res Function(PackageManifestRead) __);
}



/// @nodoc


class PackageManifestWasRead implements PackageManifestRead {
  const PackageManifestWasRead(this.manifest);
  

 final  PackageManifest manifest;

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageManifestWasReadCopyWith<PackageManifestWasRead> get copyWith => _$PackageManifestWasReadCopyWithImpl<PackageManifestWasRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageManifestWasRead&&(identical(other.manifest, manifest) || other.manifest == manifest));
}


@override
int get hashCode {
    return Object.hash(runtimeType,manifest);
}

@override
String toString() {
    return 'PackageManifestRead.read(manifest: $manifest)';
}


}

/// @nodoc
abstract mixin class $PackageManifestWasReadCopyWith<$Res> implements $PackageManifestReadCopyWith<$Res> {
  factory $PackageManifestWasReadCopyWith(PackageManifestWasRead value, $Res Function(PackageManifestWasRead) _then) = _$PackageManifestWasReadCopyWithImpl;
@useResult
$Res call({
 PackageManifest manifest
});


$PackageManifestCopyWith<$Res> get manifest;

}
/// @nodoc
class _$PackageManifestWasReadCopyWithImpl<$Res>
    implements $PackageManifestWasReadCopyWith<$Res> {
  _$PackageManifestWasReadCopyWithImpl(this._self, this._then);

  final PackageManifestWasRead _self;
  final $Res Function(PackageManifestWasRead) _then;

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? manifest = null,}) {
  return _then(PackageManifestWasRead(
null == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as PackageManifest,
  ));
}

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PackageManifestCopyWith<$Res> get manifest {
  
  return $PackageManifestCopyWith<$Res>(_self.manifest, (value) {
    return _then(_self.copyWith(manifest: value));
  });
}
}

/// @nodoc


class PackageManifestUnreadable implements PackageManifestRead {
  const PackageManifestUnreadable(this.problem);
  

 final  ManifestProblem problem;

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageManifestUnreadableCopyWith<PackageManifestUnreadable> get copyWith => _$PackageManifestUnreadableCopyWithImpl<PackageManifestUnreadable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageManifestUnreadable&&(identical(other.problem, problem) || other.problem == problem));
}


@override
int get hashCode {
    return Object.hash(runtimeType,problem);
}

@override
String toString() {
    return 'PackageManifestRead.unreadable(problem: $problem)';
}


}

/// @nodoc
abstract mixin class $PackageManifestUnreadableCopyWith<$Res> implements $PackageManifestReadCopyWith<$Res> {
  factory $PackageManifestUnreadableCopyWith(PackageManifestUnreadable value, $Res Function(PackageManifestUnreadable) _then) = _$PackageManifestUnreadableCopyWithImpl;
@useResult
$Res call({
 ManifestProblem problem
});


$ManifestProblemCopyWith<$Res> get problem;

}
/// @nodoc
class _$PackageManifestUnreadableCopyWithImpl<$Res>
    implements $PackageManifestUnreadableCopyWith<$Res> {
  _$PackageManifestUnreadableCopyWithImpl(this._self, this._then);

  final PackageManifestUnreadable _self;
  final $Res Function(PackageManifestUnreadable) _then;

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problem = null,}) {
  return _then(PackageManifestUnreadable(
null == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem,
  ));
}

/// Create a copy of PackageManifestRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res> get problem {
  
  return $ManifestProblemCopyWith<$Res>(_self.problem, (value) {
    return _then(_self.copyWith(problem: value));
  });
}
}

// dart format on
