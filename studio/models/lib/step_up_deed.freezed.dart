// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step_up_deed.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepUpDeed {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpDeed()';
}


}

/// @nodoc
class $StepUpDeedCopyWith<$Res>  {
$StepUpDeedCopyWith(StepUpDeed _, $Res Function(StepUpDeed) __);
}



/// @nodoc


class StepUpDeedSet implements StepUpDeed {
  const StepUpDeedSet(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedSetCopyWith<StepUpDeedSet> get copyWith => _$StepUpDeedSetCopyWithImpl<StepUpDeedSet>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedSet&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.set(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedSetCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedSetCopyWith(StepUpDeedSet value, $Res Function(StepUpDeedSet) _then) = _$StepUpDeedSetCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedSetCopyWithImpl<$Res>
    implements $StepUpDeedSetCopyWith<$Res> {
  _$StepUpDeedSetCopyWithImpl(this._self, this._then);

  final StepUpDeedSet _self;
  final $Res Function(StepUpDeedSet) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedSet(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedAction implements StepUpDeed {
  const StepUpDeedAction(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedActionCopyWith<StepUpDeedAction> get copyWith => _$StepUpDeedActionCopyWithImpl<StepUpDeedAction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedAction&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.action(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedActionCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedActionCopyWith(StepUpDeedAction value, $Res Function(StepUpDeedAction) _then) = _$StepUpDeedActionCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedActionCopyWithImpl<$Res>
    implements $StepUpDeedActionCopyWith<$Res> {
  _$StepUpDeedActionCopyWithImpl(this._self, this._then);

  final StepUpDeedAction _self;
  final $Res Function(StepUpDeedAction) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedAction(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedChange implements StepUpDeed {
  const StepUpDeedChange({required this.op, required this.field, required this.to});
  

 final  ChangeOp op;
 final  String field;
 final  ChangeSide to;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedChangeCopyWith<StepUpDeedChange> get copyWith => _$StepUpDeedChangeCopyWithImpl<StepUpDeedChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedChange&&(identical(other.op, op) || other.op == op)&&(identical(other.field, field) || other.field == field)&&(identical(other.to, to) || other.to == to));
}


@override
int get hashCode {
    return Object.hash(runtimeType,op,field,to);
}

@override
String toString() {
    return 'StepUpDeed.change(op: $op, field: $field, to: $to)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedChangeCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedChangeCopyWith(StepUpDeedChange value, $Res Function(StepUpDeedChange) _then) = _$StepUpDeedChangeCopyWithImpl;
@useResult
$Res call({
 ChangeOp op, String field, ChangeSide to
});


$ChangeSideCopyWith<$Res> get to;

}
/// @nodoc
class _$StepUpDeedChangeCopyWithImpl<$Res>
    implements $StepUpDeedChangeCopyWith<$Res> {
  _$StepUpDeedChangeCopyWithImpl(this._self, this._then);

  final StepUpDeedChange _self;
  final $Res Function(StepUpDeedChange) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? op = null,Object? field = null,Object? to = null,}) {
  return _then(StepUpDeedChange(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as ChangeOp,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as ChangeSide,
  ));
}

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChangeSideCopyWith<$Res> get to {
  
  return $ChangeSideCopyWith<$Res>(_self.to, (value) {
    return _then(_self.copyWith(to: value));
  });
}
}

/// @nodoc


class StepUpDeedAddUser implements StepUpDeed {
  const StepUpDeedAddUser(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedAddUserCopyWith<StepUpDeedAddUser> get copyWith => _$StepUpDeedAddUserCopyWithImpl<StepUpDeedAddUser>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedAddUser&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.addUser(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedAddUserCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedAddUserCopyWith(StepUpDeedAddUser value, $Res Function(StepUpDeedAddUser) _then) = _$StepUpDeedAddUserCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedAddUserCopyWithImpl<$Res>
    implements $StepUpDeedAddUserCopyWith<$Res> {
  _$StepUpDeedAddUserCopyWithImpl(this._self, this._then);

  final StepUpDeedAddUser _self;
  final $Res Function(StepUpDeedAddUser) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedAddUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedRemoveUser implements StepUpDeed {
  const StepUpDeedRemoveUser(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedRemoveUserCopyWith<StepUpDeedRemoveUser> get copyWith => _$StepUpDeedRemoveUserCopyWithImpl<StepUpDeedRemoveUser>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedRemoveUser&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.removeUser(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedRemoveUserCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedRemoveUserCopyWith(StepUpDeedRemoveUser value, $Res Function(StepUpDeedRemoveUser) _then) = _$StepUpDeedRemoveUserCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedRemoveUserCopyWithImpl<$Res>
    implements $StepUpDeedRemoveUserCopyWith<$Res> {
  _$StepUpDeedRemoveUserCopyWithImpl(this._self, this._then);

  final StepUpDeedRemoveUser _self;
  final $Res Function(StepUpDeedRemoveUser) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedRemoveUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedSetRoles implements StepUpDeed {
  const StepUpDeedSetRoles(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedSetRolesCopyWith<StepUpDeedSetRoles> get copyWith => _$StepUpDeedSetRolesCopyWithImpl<StepUpDeedSetRoles>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedSetRoles&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.setRoles(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedSetRolesCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedSetRolesCopyWith(StepUpDeedSetRoles value, $Res Function(StepUpDeedSetRoles) _then) = _$StepUpDeedSetRolesCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedSetRolesCopyWithImpl<$Res>
    implements $StepUpDeedSetRolesCopyWith<$Res> {
  _$StepUpDeedSetRolesCopyWithImpl(this._self, this._then);

  final StepUpDeedSetRoles _self;
  final $Res Function(StepUpDeedSetRoles) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedSetRoles(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedSetPassword implements StepUpDeed {
  const StepUpDeedSetPassword(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedSetPasswordCopyWith<StepUpDeedSetPassword> get copyWith => _$StepUpDeedSetPasswordCopyWithImpl<StepUpDeedSetPassword>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedSetPassword&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.setPassword(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedSetPasswordCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedSetPasswordCopyWith(StepUpDeedSetPassword value, $Res Function(StepUpDeedSetPassword) _then) = _$StepUpDeedSetPasswordCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedSetPasswordCopyWithImpl<$Res>
    implements $StepUpDeedSetPasswordCopyWith<$Res> {
  _$StepUpDeedSetPasswordCopyWithImpl(this._self, this._then);

  final StepUpDeedSetPassword _self;
  final $Res Function(StepUpDeedSetPassword) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedSetPassword(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedDisableUser implements StepUpDeed {
  const StepUpDeedDisableUser(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedDisableUserCopyWith<StepUpDeedDisableUser> get copyWith => _$StepUpDeedDisableUserCopyWithImpl<StepUpDeedDisableUser>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedDisableUser&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.disableUser(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedDisableUserCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedDisableUserCopyWith(StepUpDeedDisableUser value, $Res Function(StepUpDeedDisableUser) _then) = _$StepUpDeedDisableUserCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedDisableUserCopyWithImpl<$Res>
    implements $StepUpDeedDisableUserCopyWith<$Res> {
  _$StepUpDeedDisableUserCopyWithImpl(this._self, this._then);

  final StepUpDeedDisableUser _self;
  final $Res Function(StepUpDeedDisableUser) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedDisableUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedEnableUser implements StepUpDeed {
  const StepUpDeedEnableUser(this.name);
  

 final  String name;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpDeedEnableUserCopyWith<StepUpDeedEnableUser> get copyWith => _$StepUpDeedEnableUserCopyWithImpl<StepUpDeedEnableUser>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedEnableUser&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'StepUpDeed.enableUser(name: $name)';
}


}

/// @nodoc
abstract mixin class $StepUpDeedEnableUserCopyWith<$Res> implements $StepUpDeedCopyWith<$Res> {
  factory $StepUpDeedEnableUserCopyWith(StepUpDeedEnableUser value, $Res Function(StepUpDeedEnableUser) _then) = _$StepUpDeedEnableUserCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$StepUpDeedEnableUserCopyWithImpl<$Res>
    implements $StepUpDeedEnableUserCopyWith<$Res> {
  _$StepUpDeedEnableUserCopyWithImpl(this._self, this._then);

  final StepUpDeedEnableUser _self;
  final $Res Function(StepUpDeedEnableUser) _then;

/// Create a copy of StepUpDeed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(StepUpDeedEnableUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StepUpDeedRemoveDevice implements StepUpDeed {
  const StepUpDeedRemoveDevice();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpDeedRemoveDevice);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpDeed.removeDevice()';
}


}




// dart format on
