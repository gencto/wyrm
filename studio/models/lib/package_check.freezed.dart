// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_check.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageCheck {

 String get title; String get detail; PackageCheckResult get result;/// The rights the package asks for, when the check lists them (ui
/// words them; [detail] is then empty).
 IList<RequestedRight>? get rights;/// What is wrong with the manifest [file], when the check is of it:
/// ui words it ([detail] is then empty).
 ManifestProblem? get problem;/// The manifest the [problem] is of, by its name in the archive.
 String? get file;/// The link of a link backup, when the check shows it: ui words it
/// ([detail] is then empty).
 BackupLinkFacts? get link;
/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageCheckCopyWith<PackageCheck> get copyWith => _$PackageCheckCopyWithImpl<PackageCheck>(this as PackageCheck, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageCheck&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.result, _this.result) || other.result == _this.result)&&const DeepCollectionEquality().equals(other.rights, _this.rights)&&(identical(other.problem, _this.problem) || other.problem == _this.problem)&&(identical(other.file, _this.file) || other.file == _this.file)&&(identical(other.link, _this.link) || other.link == _this.link));
}


@override
int get hashCode {
  final _this = this as PackageCheck;
  return Object.hash(runtimeType,_this.title,_this.detail,_this.result,const DeepCollectionEquality().hash(_this.rights),_this.problem,_this.file,_this.link);
}

@override
String toString() {
  final _this = this as PackageCheck;
  return 'PackageCheck(title: ${_this.title}, detail: ${_this.detail}, result: ${_this.result}, rights: ${_this.rights}, problem: ${_this.problem}, file: ${_this.file}, link: ${_this.link})';
}


}

/// @nodoc
abstract mixin class $PackageCheckCopyWith<$Res>  {
  factory $PackageCheckCopyWith(PackageCheck value, $Res Function(PackageCheck) _then) = _$PackageCheckCopyWithImpl;
@useResult
$Res call({
 String title, String detail, PackageCheckResult result, IList<RequestedRight>? rights, ManifestProblem? problem, String? file, BackupLinkFacts? link
});


$ManifestProblemCopyWith<$Res>? get problem;$BackupLinkFactsCopyWith<$Res>? get link;

}
/// @nodoc
class _$PackageCheckCopyWithImpl<$Res>
    implements $PackageCheckCopyWith<$Res> {
  _$PackageCheckCopyWithImpl(this._self, this._then);

  final PackageCheck _self;
  final $Res Function(PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? detail = null,Object? result = null,Object? rights = freezed,Object? problem = freezed,Object? file = freezed,Object? link = freezed,}) {
  return _then(PackageCheck(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as PackageCheckResult,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>?,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem?,file: freezed == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String?,link: freezed == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as BackupLinkFacts?,
  ));
}
/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res>? get problem {
    if (_self.problem == null) {
    return null;
  }

  return $ManifestProblemCopyWith<$Res>(_self.problem!, (value) {
    return _then(_self.copyWith(problem: value));
  });
}/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackupLinkFactsCopyWith<$Res>? get link {
    if (_self.link == null) {
    return null;
  }

  return $BackupLinkFactsCopyWith<$Res>(_self.link!, (value) {
    return _then(_self.copyWith(link: value));
  });
}
}



/// @nodoc


class _PackageCheck implements PackageCheck {
  const _PackageCheck({required this.title, this.detail = '', this.result = PackageCheckResult.ok, this.rights, this.problem, this.file, this.link});
  

@override final  String title;
@override@JsonKey() final  String detail;
@override@JsonKey() final  PackageCheckResult result;
/// The rights the package asks for, when the check lists them (ui
/// words them; [detail] is then empty).
@override final  IList<RequestedRight>? rights;
/// What is wrong with the manifest [file], when the check is of it:
/// ui words it ([detail] is then empty).
@override final  ManifestProblem? problem;
/// The manifest the [problem] is of, by its name in the archive.
@override final  String? file;
/// The link of a link backup, when the check shows it: ui words it
/// ([detail] is then empty).
@override final  BackupLinkFacts? link;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageCheckCopyWith<_PackageCheck> get copyWith => __$PackageCheckCopyWithImpl<_PackageCheck>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageCheck&&(identical(other.title, title) || other.title == title)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.result, result) || other.result == result)&&const DeepCollectionEquality().equals(other.rights, rights)&&(identical(other.problem, problem) || other.problem == problem)&&(identical(other.file, file) || other.file == file)&&(identical(other.link, link) || other.link == link));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,detail,result,const DeepCollectionEquality().hash(rights),problem,file,link);
}

@override
String toString() {
    return 'PackageCheck(title: $title, detail: $detail, result: $result, rights: $rights, problem: $problem, file: $file, link: $link)';
}


}

/// @nodoc
abstract mixin class _$PackageCheckCopyWith<$Res> implements $PackageCheckCopyWith<$Res> {
  factory _$PackageCheckCopyWith(_PackageCheck value, $Res Function(_PackageCheck) _then) = __$PackageCheckCopyWithImpl;
@override @useResult
$Res call({
 String title, String detail, PackageCheckResult result, IList<RequestedRight>? rights, ManifestProblem? problem, String? file, BackupLinkFacts? link
});


@override $ManifestProblemCopyWith<$Res>? get problem;@override $BackupLinkFactsCopyWith<$Res>? get link;

}
/// @nodoc
class __$PackageCheckCopyWithImpl<$Res>
    implements _$PackageCheckCopyWith<$Res> {
  __$PackageCheckCopyWithImpl(this._self, this._then);

  final _PackageCheck _self;
  final $Res Function(_PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? detail = null,Object? result = null,Object? rights = freezed,Object? problem = freezed,Object? file = freezed,Object? link = freezed,}) {
  return _then(_PackageCheck(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as PackageCheckResult,rights: freezed == rights ? _self.rights : rights // ignore: cast_nullable_to_non_nullable
as IList<RequestedRight>?,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem?,file: freezed == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String?,link: freezed == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as BackupLinkFacts?,
  ));
}

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ManifestProblemCopyWith<$Res>? get problem {
    if (_self.problem == null) {
    return null;
  }

  return $ManifestProblemCopyWith<$Res>(_self.problem!, (value) {
    return _then(_self.copyWith(problem: value));
  });
}/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackupLinkFactsCopyWith<$Res>? get link {
    if (_self.link == null) {
    return null;
  }

  return $BackupLinkFactsCopyWith<$Res>(_self.link!, (value) {
    return _then(_self.copyWith(link: value));
  });
}
}

// dart format on
