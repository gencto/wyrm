// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'restore_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RestoreRecord {

 RestoreEnd get end;/// When it was written, in Unix seconds.
 int get seconds;/// The broker's words: the sections, or why it failed.
 String? get detail;
/// Create a copy of RestoreRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestoreRecordCopyWith<RestoreRecord> get copyWith => _$RestoreRecordCopyWithImpl<RestoreRecord>(this as RestoreRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RestoreRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreRecord&&(identical(other.end, _this.end) || other.end == _this.end)&&(identical(other.seconds, _this.seconds) || other.seconds == _this.seconds)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as RestoreRecord;
  return Object.hash(runtimeType,_this.end,_this.seconds,_this.detail);
}

@override
String toString() {
  final _this = this as RestoreRecord;
  return 'RestoreRecord(end: ${_this.end}, seconds: ${_this.seconds}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $RestoreRecordCopyWith<$Res>  {
  factory $RestoreRecordCopyWith(RestoreRecord value, $Res Function(RestoreRecord) _then) = _$RestoreRecordCopyWithImpl;
@useResult
$Res call({
 RestoreEnd end, int seconds, String? detail
});




}
/// @nodoc
class _$RestoreRecordCopyWithImpl<$Res>
    implements $RestoreRecordCopyWith<$Res> {
  _$RestoreRecordCopyWithImpl(this._self, this._then);

  final RestoreRecord _self;
  final $Res Function(RestoreRecord) _then;

/// Create a copy of RestoreRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? end = null,Object? seconds = null,Object? detail = freezed,}) {
  return _then(RestoreRecord(
end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as RestoreEnd,seconds: null == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as int,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _RestoreRecord implements RestoreRecord {
  const _RestoreRecord({required this.end, required this.seconds, this.detail});
  

@override final  RestoreEnd end;
/// When it was written, in Unix seconds.
@override final  int seconds;
/// The broker's words: the sections, or why it failed.
@override final  String? detail;

/// Create a copy of RestoreRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreRecordCopyWith<_RestoreRecord> get copyWith => __$RestoreRecordCopyWithImpl<_RestoreRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreRecord&&(identical(other.end, end) || other.end == end)&&(identical(other.seconds, seconds) || other.seconds == seconds)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,end,seconds,detail);
}

@override
String toString() {
    return 'RestoreRecord(end: $end, seconds: $seconds, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$RestoreRecordCopyWith<$Res> implements $RestoreRecordCopyWith<$Res> {
  factory _$RestoreRecordCopyWith(_RestoreRecord value, $Res Function(_RestoreRecord) _then) = __$RestoreRecordCopyWithImpl;
@override @useResult
$Res call({
 RestoreEnd end, int seconds, String? detail
});




}
/// @nodoc
class __$RestoreRecordCopyWithImpl<$Res>
    implements _$RestoreRecordCopyWith<$Res> {
  __$RestoreRecordCopyWithImpl(this._self, this._then);

  final _RestoreRecord _self;
  final $Res Function(_RestoreRecord) _then;

/// Create a copy of RestoreRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? end = null,Object? seconds = null,Object? detail = freezed,}) {
  return _then(_RestoreRecord(
end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as RestoreEnd,seconds: null == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as int,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
