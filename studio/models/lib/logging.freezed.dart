// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'logging.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Logging {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Logging);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Logging()';
}


}

/// @nodoc
class $LoggingCopyWith<$Res>  {
$LoggingCopyWith(Logging _, $Res Function(Logging) __);
}



/// @nodoc


class LoggingKnown implements Logging {
  const LoggingKnown(this.type);
  

 final  LoggingType type;

/// Create a copy of Logging
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoggingKnownCopyWith<LoggingKnown> get copyWith => _$LoggingKnownCopyWithImpl<LoggingKnown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoggingKnown&&(identical(other.type, type) || other.type == type));
}


@override
int get hashCode {
    return Object.hash(runtimeType,type);
}

@override
String toString() {
    return 'Logging.known(type: $type)';
}


}

/// @nodoc
abstract mixin class $LoggingKnownCopyWith<$Res> implements $LoggingCopyWith<$Res> {
  factory $LoggingKnownCopyWith(LoggingKnown value, $Res Function(LoggingKnown) _then) = _$LoggingKnownCopyWithImpl;
@useResult
$Res call({
 LoggingType type
});




}
/// @nodoc
class _$LoggingKnownCopyWithImpl<$Res>
    implements $LoggingKnownCopyWith<$Res> {
  _$LoggingKnownCopyWithImpl(this._self, this._then);

  final LoggingKnown _self;
  final $Res Function(LoggingKnown) _then;

/// Create a copy of Logging
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? type = null,}) {
  return _then(LoggingKnown(
null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as LoggingType,
  ));
}


}

/// @nodoc


class LoggingOther implements Logging {
  const LoggingOther(this.name);
  

 final  String name;

/// Create a copy of Logging
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoggingOtherCopyWith<LoggingOther> get copyWith => _$LoggingOtherCopyWithImpl<LoggingOther>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoggingOther&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'Logging.other(name: $name)';
}


}

/// @nodoc
abstract mixin class $LoggingOtherCopyWith<$Res> implements $LoggingCopyWith<$Res> {
  factory $LoggingOtherCopyWith(LoggingOther value, $Res Function(LoggingOther) _then) = _$LoggingOtherCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$LoggingOtherCopyWithImpl<$Res>
    implements $LoggingOtherCopyWith<$Res> {
  _$LoggingOtherCopyWithImpl(this._self, this._then);

  final LoggingOther _self;
  final $Res Function(LoggingOther) _then;

/// Create a copy of Logging
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(LoggingOther(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
