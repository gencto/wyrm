// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'audit_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuditEntry {

 DateTime get time;/// `set`, `invoke`, `login`, …
 String get op;/// The key it was on (`…/~set`, `…/~act/<a>`).
 String get key;/// Who did it (`user:admin`, `claimed:flow:<id>`).
 String get who;/// 0 = done; else the refusal's status code.
 int get status;
/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuditEntryCopyWith<AuditEntry> get copyWith => _$AuditEntryCopyWithImpl<AuditEntry>(this as AuditEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AuditEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuditEntry&&(identical(other.time, _this.time) || other.time == _this.time)&&(identical(other.op, _this.op) || other.op == _this.op)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.who, _this.who) || other.who == _this.who)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as AuditEntry;
  return Object.hash(runtimeType,_this.time,_this.op,_this.key,_this.who,_this.status);
}

@override
String toString() {
  final _this = this as AuditEntry;
  return 'AuditEntry(time: ${_this.time}, op: ${_this.op}, key: ${_this.key}, who: ${_this.who}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $AuditEntryCopyWith<$Res>  {
  factory $AuditEntryCopyWith(AuditEntry value, $Res Function(AuditEntry) _then) = _$AuditEntryCopyWithImpl;
@useResult
$Res call({
 DateTime time, String op, String key, String who, int status
});




}
/// @nodoc
class _$AuditEntryCopyWithImpl<$Res>
    implements $AuditEntryCopyWith<$Res> {
  _$AuditEntryCopyWithImpl(this._self, this._then);

  final AuditEntry _self;
  final $Res Function(AuditEntry) _then;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? op = null,Object? key = null,Object? who = null,Object? status = null,}) {
  return _then(AuditEntry(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,who: null == who ? _self.who : who // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _AuditEntry implements AuditEntry {
  const _AuditEntry({required this.time, required this.op, required this.key, required this.who, this.status = 0});
  

@override final  DateTime time;
/// `set`, `invoke`, `login`, …
@override final  String op;
/// The key it was on (`…/~set`, `…/~act/<a>`).
@override final  String key;
/// Who did it (`user:admin`, `claimed:flow:<id>`).
@override final  String who;
/// 0 = done; else the refusal's status code.
@override@JsonKey() final  int status;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuditEntryCopyWith<_AuditEntry> get copyWith => __$AuditEntryCopyWithImpl<_AuditEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuditEntry&&(identical(other.time, time) || other.time == time)&&(identical(other.op, op) || other.op == op)&&(identical(other.key, key) || other.key == key)&&(identical(other.who, who) || other.who == who)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,time,op,key,who,status);
}

@override
String toString() {
    return 'AuditEntry(time: $time, op: $op, key: $key, who: $who, status: $status)';
}


}

/// @nodoc
abstract mixin class _$AuditEntryCopyWith<$Res> implements $AuditEntryCopyWith<$Res> {
  factory _$AuditEntryCopyWith(_AuditEntry value, $Res Function(_AuditEntry) _then) = __$AuditEntryCopyWithImpl;
@override @useResult
$Res call({
 DateTime time, String op, String key, String who, int status
});




}
/// @nodoc
class __$AuditEntryCopyWithImpl<$Res>
    implements _$AuditEntryCopyWith<$Res> {
  __$AuditEntryCopyWithImpl(this._self, this._then);

  final _AuditEntry _self;
  final $Res Function(_AuditEntry) _then;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? op = null,Object? key = null,Object? who = null,Object? status = null,}) {
  return _then(_AuditEntry(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,who: null == who ? _self.who : who // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
