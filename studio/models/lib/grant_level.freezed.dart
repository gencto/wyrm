// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'grant_level.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GrantLevel {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GrantLevel);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GrantLevel()';
}


}

/// @nodoc
class $GrantLevelCopyWith<$Res>  {
$GrantLevelCopyWith(GrantLevel _, $Res Function(GrantLevel) __);
}



/// @nodoc


class GrantLevelPerm implements GrantLevel {
  const GrantLevelPerm(this.perm);
  

 final  Perm perm;

/// Create a copy of GrantLevel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GrantLevelPermCopyWith<GrantLevelPerm> get copyWith => _$GrantLevelPermCopyWithImpl<GrantLevelPerm>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GrantLevelPerm&&(identical(other.perm, perm) || other.perm == perm));
}


@override
int get hashCode {
    return Object.hash(runtimeType,perm);
}

@override
String toString() {
    return 'GrantLevel.perm(perm: $perm)';
}


}

/// @nodoc
abstract mixin class $GrantLevelPermCopyWith<$Res> implements $GrantLevelCopyWith<$Res> {
  factory $GrantLevelPermCopyWith(GrantLevelPerm value, $Res Function(GrantLevelPerm) _then) = _$GrantLevelPermCopyWithImpl;
@useResult
$Res call({
 Perm perm
});




}
/// @nodoc
class _$GrantLevelPermCopyWithImpl<$Res>
    implements $GrantLevelPermCopyWith<$Res> {
  _$GrantLevelPermCopyWithImpl(this._self, this._then);

  final GrantLevelPerm _self;
  final $Res Function(GrantLevelPerm) _then;

/// Create a copy of GrantLevel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? perm = null,}) {
  return _then(GrantLevelPerm(
null == perm ? _self.perm : perm // ignore: cast_nullable_to_non_nullable
as Perm,
  ));
}


}

/// @nodoc


class GrantLevelRule implements GrantLevel {
  const GrantLevelRule(this.text);
  

 final  String text;

/// Create a copy of GrantLevel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GrantLevelRuleCopyWith<GrantLevelRule> get copyWith => _$GrantLevelRuleCopyWithImpl<GrantLevelRule>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GrantLevelRule&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'GrantLevel.rule(text: $text)';
}


}

/// @nodoc
abstract mixin class $GrantLevelRuleCopyWith<$Res> implements $GrantLevelCopyWith<$Res> {
  factory $GrantLevelRuleCopyWith(GrantLevelRule value, $Res Function(GrantLevelRule) _then) = _$GrantLevelRuleCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$GrantLevelRuleCopyWithImpl<$Res>
    implements $GrantLevelRuleCopyWith<$Res> {
  _$GrantLevelRuleCopyWithImpl(this._self, this._then);

  final GrantLevelRule _self;
  final $Res Function(GrantLevelRule) _then;

/// Create a copy of GrantLevel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(GrantLevelRule(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
