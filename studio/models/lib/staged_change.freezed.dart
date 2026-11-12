// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'staged_change.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StagedChange {

/// Unique within the session.
 String get id;/// `Edit`, `Add` or `Remove`, as the review card says it.
 String get op;/// The node or value the change is on.
 String get key;/// What changes (`poll`, `value`, `params`).
 String get field;/// Shown in ember/new.
 String get to;/// Shown struck through.
 String get from;/// `write` or `config`.
 String get level;/// For a set: the value written to `key`.
 Object? get value;/// For an invoke: the action and its arguments.
 String? get action; IMap<String, Object?> get args;
/// Create a copy of StagedChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StagedChangeCopyWith<StagedChange> get copyWith => _$StagedChangeCopyWithImpl<StagedChange>(this as StagedChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StagedChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StagedChange&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.op, _this.op) || other.op == _this.op)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.to, _this.to) || other.to == _this.to)&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.level, _this.level) || other.level == _this.level)&&const DeepCollectionEquality().equals(other.value, _this.value)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.args, _this.args) || other.args == _this.args));
}


@override
int get hashCode {
  final _this = this as StagedChange;
  return Object.hash(runtimeType,_this.id,_this.op,_this.key,_this.field,_this.to,_this.from,_this.level,const DeepCollectionEquality().hash(_this.value),_this.action,_this.args);
}

@override
String toString() {
  final _this = this as StagedChange;
  return 'StagedChange(id: ${_this.id}, op: ${_this.op}, key: ${_this.key}, field: ${_this.field}, to: ${_this.to}, from: ${_this.from}, level: ${_this.level}, value: ${_this.value}, action: ${_this.action}, args: ${_this.args})';
}


}

/// @nodoc
abstract mixin class $StagedChangeCopyWith<$Res>  {
  factory $StagedChangeCopyWith(StagedChange value, $Res Function(StagedChange) _then) = _$StagedChangeCopyWithImpl;
@useResult
$Res call({
 String id, String op, String key, String field, String to, String from, String level, Object? value, String? action, IMap<String, Object?> args
});




}
/// @nodoc
class _$StagedChangeCopyWithImpl<$Res>
    implements $StagedChangeCopyWith<$Res> {
  _$StagedChangeCopyWithImpl(this._self, this._then);

  final StagedChange _self;
  final $Res Function(StagedChange) _then;

/// Create a copy of StagedChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? op = null,Object? key = null,Object? field = null,Object? to = null,Object? from = null,Object? level = null,Object? value = freezed,Object? action = freezed,Object? args = null,}) {
  return _then(StagedChange(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value ,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}

}



/// @nodoc


class _StagedChange implements StagedChange {
  const _StagedChange({required this.id, required this.op, required this.key, required this.field, required this.to, this.from = '—', this.level = 'write', this.value, this.action, this.args = const IMapConst({})});
  

/// Unique within the session.
@override final  String id;
/// `Edit`, `Add` or `Remove`, as the review card says it.
@override final  String op;
/// The node or value the change is on.
@override final  String key;
/// What changes (`poll`, `value`, `params`).
@override final  String field;
/// Shown in ember/new.
@override final  String to;
/// Shown struck through.
@override@JsonKey() final  String from;
/// `write` or `config`.
@override@JsonKey() final  String level;
/// For a set: the value written to `key`.
@override final  Object? value;
/// For an invoke: the action and its arguments.
@override final  String? action;
@override@JsonKey() final  IMap<String, Object?> args;

/// Create a copy of StagedChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StagedChangeCopyWith<_StagedChange> get copyWith => __$StagedChangeCopyWithImpl<_StagedChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StagedChange&&(identical(other.id, id) || other.id == id)&&(identical(other.op, op) || other.op == op)&&(identical(other.key, key) || other.key == key)&&(identical(other.field, field) || other.field == field)&&(identical(other.to, to) || other.to == to)&&(identical(other.from, from) || other.from == from)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,op,key,field,to,from,level,const DeepCollectionEquality().hash(value),action,args);
}

@override
String toString() {
    return 'StagedChange(id: $id, op: $op, key: $key, field: $field, to: $to, from: $from, level: $level, value: $value, action: $action, args: $args)';
}


}

/// @nodoc
abstract mixin class _$StagedChangeCopyWith<$Res> implements $StagedChangeCopyWith<$Res> {
  factory _$StagedChangeCopyWith(_StagedChange value, $Res Function(_StagedChange) _then) = __$StagedChangeCopyWithImpl;
@override @useResult
$Res call({
 String id, String op, String key, String field, String to, String from, String level, Object? value, String? action, IMap<String, Object?> args
});




}
/// @nodoc
class __$StagedChangeCopyWithImpl<$Res>
    implements _$StagedChangeCopyWith<$Res> {
  __$StagedChangeCopyWithImpl(this._self, this._then);

  final _StagedChange _self;
  final $Res Function(_StagedChange) _then;

/// Create a copy of StagedChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? op = null,Object? key = null,Object? field = null,Object? to = null,Object? from = null,Object? level = null,Object? value = freezed,Object? action = freezed,Object? args = null,}) {
  return _then(_StagedChange(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value ,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}


}

// dart format on
