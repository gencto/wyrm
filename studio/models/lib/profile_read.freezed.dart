// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_read.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProfileRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ProfileRead()';
}


}

/// @nodoc
class $ProfileReadCopyWith<$Res>  {
$ProfileReadCopyWith(ProfileRead _, $Res Function(ProfileRead) __);
}



/// @nodoc


class ProfileWasRead implements ProfileRead {
  const ProfileWasRead(this.draft);
  

 final  ProfileDraft draft;

/// Create a copy of ProfileRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileWasReadCopyWith<ProfileWasRead> get copyWith => _$ProfileWasReadCopyWithImpl<ProfileWasRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileWasRead&&(identical(other.draft, draft) || other.draft == draft));
}


@override
int get hashCode {
    return Object.hash(runtimeType,draft);
}

@override
String toString() {
    return 'ProfileRead.read(draft: $draft)';
}


}

/// @nodoc
abstract mixin class $ProfileWasReadCopyWith<$Res> implements $ProfileReadCopyWith<$Res> {
  factory $ProfileWasReadCopyWith(ProfileWasRead value, $Res Function(ProfileWasRead) _then) = _$ProfileWasReadCopyWithImpl;
@useResult
$Res call({
 ProfileDraft draft
});


$ProfileDraftCopyWith<$Res> get draft;

}
/// @nodoc
class _$ProfileWasReadCopyWithImpl<$Res>
    implements $ProfileWasReadCopyWith<$Res> {
  _$ProfileWasReadCopyWithImpl(this._self, this._then);

  final ProfileWasRead _self;
  final $Res Function(ProfileWasRead) _then;

/// Create a copy of ProfileRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? draft = null,}) {
  return _then(ProfileWasRead(
null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as ProfileDraft,
  ));
}

/// Create a copy of ProfileRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileDraftCopyWith<$Res> get draft {
  
  return $ProfileDraftCopyWith<$Res>(_self.draft, (value) {
    return _then(_self.copyWith(draft: value));
  });
}
}

/// @nodoc


class ProfileUnreadable implements ProfileRead {
  const ProfileUnreadable(this.problem);
  

 final  ManifestProblem problem;

/// Create a copy of ProfileRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileUnreadableCopyWith<ProfileUnreadable> get copyWith => _$ProfileUnreadableCopyWithImpl<ProfileUnreadable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileUnreadable&&(identical(other.problem, problem) || other.problem == problem));
}


@override
int get hashCode {
    return Object.hash(runtimeType,problem);
}

@override
String toString() {
    return 'ProfileRead.unreadable(problem: $problem)';
}


}

/// @nodoc
abstract mixin class $ProfileUnreadableCopyWith<$Res> implements $ProfileReadCopyWith<$Res> {
  factory $ProfileUnreadableCopyWith(ProfileUnreadable value, $Res Function(ProfileUnreadable) _then) = _$ProfileUnreadableCopyWithImpl;
@useResult
$Res call({
 ManifestProblem problem
});


$ManifestProblemCopyWith<$Res> get problem;

}
/// @nodoc
class _$ProfileUnreadableCopyWithImpl<$Res>
    implements $ProfileUnreadableCopyWith<$Res> {
  _$ProfileUnreadableCopyWithImpl(this._self, this._then);

  final ProfileUnreadable _self;
  final $Res Function(ProfileUnreadable) _then;

/// Create a copy of ProfileRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problem = null,}) {
  return _then(ProfileUnreadable(
null == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as ManifestProblem,
  ));
}

/// Create a copy of ProfileRead
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
