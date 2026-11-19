// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupManifest {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupManifest);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BackupManifest()';
}


}

/// @nodoc
class $BackupManifestCopyWith<$Res>  {
$BackupManifestCopyWith(BackupManifest _, $Res Function(BackupManifest) __);
}



/// @nodoc


class LinkBackupManifest implements BackupManifest {
  const LinkBackupManifest({required this.format, required this.link, required this.sealed, required this.package, required this.version, required this.sections, required this.pretty});
  

/// `wyrm_backup`: the version of the format.
 final  int format;
/// The link, and where and when the backup was made.
 final  BackupLinkFacts link;
 final  BackupSealed sealed;
/// The package the link runs (empty: a built-in driver) and its
/// version.
 final  String package;
 final  String version;
 final  IList<BackupSection> sections;
/// The manifest as indented JSON, without its files and seals: its
/// `link` as the file writes it.
 final  String pretty;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkBackupManifestCopyWith<LinkBackupManifest> get copyWith => _$LinkBackupManifestCopyWithImpl<LinkBackupManifest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkBackupManifest&&(identical(other.format, format) || other.format == format)&&(identical(other.link, link) || other.link == link)&&(identical(other.sealed, sealed) || other.sealed == sealed)&&(identical(other.package, package) || other.package == package)&&(identical(other.version, version) || other.version == version)&&const DeepCollectionEquality().equals(other.sections, sections)&&(identical(other.pretty, pretty) || other.pretty == pretty));
}


@override
int get hashCode {
    return Object.hash(runtimeType,format,link,sealed,package,version,const DeepCollectionEquality().hash(sections),pretty);
}

@override
String toString() {
    return 'BackupManifest.link(format: $format, link: $link, sealed: $sealed, package: $package, version: $version, sections: $sections, pretty: $pretty)';
}


}

/// @nodoc
abstract mixin class $LinkBackupManifestCopyWith<$Res> implements $BackupManifestCopyWith<$Res> {
  factory $LinkBackupManifestCopyWith(LinkBackupManifest value, $Res Function(LinkBackupManifest) _then) = _$LinkBackupManifestCopyWithImpl;
@useResult
$Res call({
 int format, BackupLinkFacts link, BackupSealed sealed, String package, String version, IList<BackupSection> sections, String pretty
});


$BackupLinkFactsCopyWith<$Res> get link;

}
/// @nodoc
class _$LinkBackupManifestCopyWithImpl<$Res>
    implements $LinkBackupManifestCopyWith<$Res> {
  _$LinkBackupManifestCopyWithImpl(this._self, this._then);

  final LinkBackupManifest _self;
  final $Res Function(LinkBackupManifest) _then;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? format = null,Object? link = null,Object? sealed = null,Object? package = null,Object? version = null,Object? sections = null,Object? pretty = null,}) {
  return _then(LinkBackupManifest(
format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as int,link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as BackupLinkFacts,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as BackupSealed,package: null == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,pretty: null == pretty ? _self.pretty : pretty // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of BackupManifest
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


class OtherBackupManifest implements BackupManifest {
  const OtherBackupManifest(this.kind);
  

 final  String kind;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OtherBackupManifestCopyWith<OtherBackupManifest> get copyWith => _$OtherBackupManifestCopyWithImpl<OtherBackupManifest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OtherBackupManifest&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind);
}

@override
String toString() {
    return 'BackupManifest.other(kind: $kind)';
}


}

/// @nodoc
abstract mixin class $OtherBackupManifestCopyWith<$Res> implements $BackupManifestCopyWith<$Res> {
  factory $OtherBackupManifestCopyWith(OtherBackupManifest value, $Res Function(OtherBackupManifest) _then) = _$OtherBackupManifestCopyWithImpl;
@useResult
$Res call({
 String kind
});




}
/// @nodoc
class _$OtherBackupManifestCopyWithImpl<$Res>
    implements $OtherBackupManifestCopyWith<$Res> {
  _$OtherBackupManifestCopyWithImpl(this._self, this._then);

  final OtherBackupManifest _self;
  final $Res Function(OtherBackupManifest) _then;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,}) {
  return _then(OtherBackupManifest(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UnreadableBackupManifest implements BackupManifest {
  const UnreadableBackupManifest(this.problem);
  

 final  ManifestProblem problem;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnreadableBackupManifestCopyWith<UnreadableBackupManifest> get copyWith => _$UnreadableBackupManifestCopyWithImpl<UnreadableBackupManifest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnreadableBackupManifest&&(identical(other.problem, problem) || other.problem == problem));
}


@override
int get hashCode {
    return Object.hash(runtimeType,problem);
}

@override
String toString() {
    return 'BackupManifest.unreadable(problem: $problem)';
}


}

/// @nodoc
abstract mixin class $UnreadableBackupManifestCopyWith<$Res> implements $BackupManifestCopyWith<$Res> {
  factory $UnreadableBackupManifestCopyWith(UnreadableBackupManifest value, $Res Function(UnreadableBackupManifest) _then) = _$UnreadableBackupManifestCopyWithImpl;
@useResult
$Res call({
 ManifestProblem problem
});


$ManifestProblemCopyWith<$Res> get problem;

}
/// @nodoc
class _$UnreadableBackupManifestCopyWithImpl<$Res>
    implements $UnreadableBackupManifestCopyWith<$Res> {
  _$UnreadableBackupManifestCopyWithImpl(this._self, this._then);

  final UnreadableBackupManifest _self;
  final $Res Function(UnreadableBackupManifest) _then;

/// Create a copy of BackupManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problem = null,}) {
  return _then(UnreadableBackupManifest(
null == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem,
  ));
}

/// Create a copy of BackupManifest
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
