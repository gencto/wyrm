// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageReport {

 IList<PackageCheck> get checks; String? get manifest; String? get name; LinkMode? get kind; IList<RequestedRight>? get rights;
/// Create a copy of PackageReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageReportCopyWith<PackageReport> get copyWith => _$PackageReportCopyWithImpl<PackageReport>(this as PackageReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageReport&&const DeepCollectionEquality().equals(other.checks, _this.checks)&&(identical(other.manifest, _this.manifest) || other.manifest == _this.manifest)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&const DeepCollectionEquality().equals(other.rights, _this.rights));
}


@override
int get hashCode {
  final _this = this as PackageReport;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.checks),_this.manifest,_this.name,_this.kind,const DeepCollectionEquality().hash(_this.rights));
}

@override
String toString() {
  final _this = this as PackageReport;
  return 'PackageReport(checks: ${_this.checks}, manifest: ${_this.manifest}, name: ${_this.name}, kind: ${_this.kind}, rights: ${_this.rights})';
}


}

/// @nodoc
abstract mixin class $PackageReportCopyWith<$Res>  {
  factory $PackageReportCopyWith(PackageReport value, $Res Function(PackageReport) _then) = _$PackageReportCopyWithImpl;
@useResult
$Res call({
 IList<PackageCheck> checks, String? manifest, String? name, LinkMode? kind, IList<RequestedRight>? rights
});




}
/// @nodoc
class _$PackageReportCopyWithImpl<$Res>
    implements $PackageReportCopyWith<$Res> {
  _$PackageReportCopyWithImpl(this._self, this._then);

  final PackageReport _self;
  final $Res Function(PackageReport) _then;

/// Create a copy of PackageReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? checks = null,Object? manifest = freezed,Object? name = freezed,Object? kind = freezed,Object? rights = freezed,}) {
  return _then(PackageReport(
checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,manifest: freezed == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as LinkMode?,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>?,
  ));
}

}



/// @nodoc


class _PackageReport implements PackageReport {
  const _PackageReport({required this.checks, this.manifest, this.name, this.kind, this.rights});
  

@override final  IList<PackageCheck> checks;
@override final  String? manifest;
@override final  String? name;
@override final  LinkMode? kind;
@override final  IList<RequestedRight>? rights;

/// Create a copy of PackageReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageReportCopyWith<_PackageReport> get copyWith => __$PackageReportCopyWithImpl<_PackageReport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageReport&&const DeepCollectionEquality().equals(other.checks, checks)&&(identical(other.manifest, manifest) || other.manifest == manifest)&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&const DeepCollectionEquality().equals(other.rights, rights));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(checks),manifest,name,kind,const DeepCollectionEquality().hash(rights));
}

@override
String toString() {
    return 'PackageReport(checks: $checks, manifest: $manifest, name: $name, kind: $kind, rights: $rights)';
}


}

/// @nodoc
abstract mixin class _$PackageReportCopyWith<$Res> implements $PackageReportCopyWith<$Res> {
  factory _$PackageReportCopyWith(_PackageReport value, $Res Function(_PackageReport) _then) = __$PackageReportCopyWithImpl;
@override @useResult
$Res call({
 IList<PackageCheck> checks, String? manifest, String? name, LinkMode? kind, IList<RequestedRight>? rights
});




}
/// @nodoc
class __$PackageReportCopyWithImpl<$Res>
    implements _$PackageReportCopyWith<$Res> {
  __$PackageReportCopyWithImpl(this._self, this._then);

  final _PackageReport _self;
  final $Res Function(_PackageReport) _then;

/// Create a copy of PackageReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? checks = null,Object? manifest = freezed,Object? name = freezed,Object? kind = freezed,Object? rights = freezed,}) {
  return _then(_PackageReport(
checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,manifest: freezed == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as LinkMode?,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>?,
  ));
}


}

// dart format on
