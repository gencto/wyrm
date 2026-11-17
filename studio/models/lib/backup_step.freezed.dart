// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_step.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupStep {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupStep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BackupStep()';
}


}

/// @nodoc
class $BackupStepCopyWith<$Res>  {
$BackupStepCopyWith(BackupStep _, $Res Function(BackupStep) __);
}



/// @nodoc


class BackupStepNone implements BackupStep {
  const BackupStepNone();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupStepNone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BackupStep.none()';
}


}




/// @nodoc


class BackupStepSection implements BackupStep {
  const BackupStepSection(this.section);
  

 final  BackupSection section;

/// Create a copy of BackupStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupStepSectionCopyWith<BackupStepSection> get copyWith => _$BackupStepSectionCopyWithImpl<BackupStepSection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupStepSection&&(identical(other.section, section) || other.section == section));
}


@override
int get hashCode {
    return Object.hash(runtimeType,section);
}

@override
String toString() {
    return 'BackupStep.section(section: $section)';
}


}

/// @nodoc
abstract mixin class $BackupStepSectionCopyWith<$Res> implements $BackupStepCopyWith<$Res> {
  factory $BackupStepSectionCopyWith(BackupStepSection value, $Res Function(BackupStepSection) _then) = _$BackupStepSectionCopyWithImpl;
@useResult
$Res call({
 BackupSection section
});




}
/// @nodoc
class _$BackupStepSectionCopyWithImpl<$Res>
    implements $BackupStepSectionCopyWith<$Res> {
  _$BackupStepSectionCopyWithImpl(this._self, this._then);

  final BackupStepSection _self;
  final $Res Function(BackupStepSection) _then;

/// Create a copy of BackupStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? section = null,}) {
  return _then(BackupStepSection(
null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as BackupSection,
  ));
}


}

/// @nodoc


class BackupStepWriting implements BackupStep {
  const BackupStepWriting();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupStepWriting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BackupStep.writing()';
}


}




// dart format on
