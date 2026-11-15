// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sys_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SysStatus {

 IMap<SysValue, num> get numbers;/// `sys/version`, `sys/zenoh_version`, `sys/distribution`.
 String? get version; String? get zenohVersion; String? get distribution;/// `sys/start_time`.
 DateTime? get startTime;/// `sys/log_level`.
 LogLevel? get logLevel;
/// Create a copy of SysStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SysStatusCopyWith<SysStatus> get copyWith => _$SysStatusCopyWithImpl<SysStatus>(this as SysStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SysStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SysStatus&&(identical(other.numbers, _this.numbers) || other.numbers == _this.numbers)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.zenohVersion, _this.zenohVersion) || other.zenohVersion == _this.zenohVersion)&&(identical(other.distribution, _this.distribution) || other.distribution == _this.distribution)&&(identical(other.startTime, _this.startTime) || other.startTime == _this.startTime)&&(identical(other.logLevel, _this.logLevel) || other.logLevel == _this.logLevel));
}


@override
int get hashCode {
  final _this = this as SysStatus;
  return Object.hash(runtimeType,_this.numbers,_this.version,_this.zenohVersion,_this.distribution,_this.startTime,_this.logLevel);
}

@override
String toString() {
  final _this = this as SysStatus;
  return 'SysStatus(numbers: ${_this.numbers}, version: ${_this.version}, zenohVersion: ${_this.zenohVersion}, distribution: ${_this.distribution}, startTime: ${_this.startTime}, logLevel: ${_this.logLevel})';
}


}

/// @nodoc
abstract mixin class $SysStatusCopyWith<$Res>  {
  factory $SysStatusCopyWith(SysStatus value, $Res Function(SysStatus) _then) = _$SysStatusCopyWithImpl;
@useResult
$Res call({
 IMap<SysValue, num> numbers, String? version, String? zenohVersion, String? distribution, DateTime? startTime, LogLevel? logLevel
});




}
/// @nodoc
class _$SysStatusCopyWithImpl<$Res>
    implements $SysStatusCopyWith<$Res> {
  _$SysStatusCopyWithImpl(this._self, this._then);

  final SysStatus _self;
  final $Res Function(SysStatus) _then;

/// Create a copy of SysStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? numbers = null,Object? version = freezed,Object? zenohVersion = freezed,Object? distribution = freezed,Object? startTime = freezed,Object? logLevel = freezed,}) {
  return _then(SysStatus(
numbers: null == numbers ? _self.numbers : numbers // ignore: cast_nullable_to_non_nullable
as IMap<SysValue, num>,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,zenohVersion: freezed == zenohVersion ? _self.zenohVersion : zenohVersion // ignore: cast_nullable_to_non_nullable
as String?,distribution: freezed == distribution ? _self.distribution : distribution // ignore: cast_nullable_to_non_nullable
as String?,startTime: freezed == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime?,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as LogLevel?,
  ));
}

}



/// @nodoc


class _SysStatus extends SysStatus {
  const _SysStatus({this.numbers = const IMapConst({}), this.version, this.zenohVersion, this.distribution, this.startTime, this.logLevel}): super._();
  

@override@JsonKey() final  IMap<SysValue, num> numbers;
/// `sys/version`, `sys/zenoh_version`, `sys/distribution`.
@override final  String? version;
@override final  String? zenohVersion;
@override final  String? distribution;
/// `sys/start_time`.
@override final  DateTime? startTime;
/// `sys/log_level`.
@override final  LogLevel? logLevel;

/// Create a copy of SysStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SysStatusCopyWith<_SysStatus> get copyWith => __$SysStatusCopyWithImpl<_SysStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SysStatus&&(identical(other.numbers, numbers) || other.numbers == numbers)&&(identical(other.version, version) || other.version == version)&&(identical(other.zenohVersion, zenohVersion) || other.zenohVersion == zenohVersion)&&(identical(other.distribution, distribution) || other.distribution == distribution)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,numbers,version,zenohVersion,distribution,startTime,logLevel);
}

@override
String toString() {
    return 'SysStatus(numbers: $numbers, version: $version, zenohVersion: $zenohVersion, distribution: $distribution, startTime: $startTime, logLevel: $logLevel)';
}


}

/// @nodoc
abstract mixin class _$SysStatusCopyWith<$Res> implements $SysStatusCopyWith<$Res> {
  factory _$SysStatusCopyWith(_SysStatus value, $Res Function(_SysStatus) _then) = __$SysStatusCopyWithImpl;
@override @useResult
$Res call({
 IMap<SysValue, num> numbers, String? version, String? zenohVersion, String? distribution, DateTime? startTime, LogLevel? logLevel
});




}
/// @nodoc
class __$SysStatusCopyWithImpl<$Res>
    implements _$SysStatusCopyWith<$Res> {
  __$SysStatusCopyWithImpl(this._self, this._then);

  final _SysStatus _self;
  final $Res Function(_SysStatus) _then;

/// Create a copy of SysStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? numbers = null,Object? version = freezed,Object? zenohVersion = freezed,Object? distribution = freezed,Object? startTime = freezed,Object? logLevel = freezed,}) {
  return _then(_SysStatus(
numbers: null == numbers ? _self.numbers : numbers // ignore: cast_nullable_to_non_nullable
as IMap<SysValue, num>,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,zenohVersion: freezed == zenohVersion ? _self.zenohVersion : zenohVersion // ignore: cast_nullable_to_non_nullable
as String?,distribution: freezed == distribution ? _self.distribution : distribution // ignore: cast_nullable_to_non_nullable
as String?,startTime: freezed == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime?,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as LogLevel?,
  ));
}


}

// dart format on
