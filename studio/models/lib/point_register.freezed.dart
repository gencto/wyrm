// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'point_register.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PointRegister {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PointRegister);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PointRegister()';
}


}

/// @nodoc
class $PointRegisterCopyWith<$Res>  {
$PointRegisterCopyWith(PointRegister _, $Res Function(PointRegister) __);
}



/// @nodoc


class ModbusRegister implements PointRegister {
  const ModbusRegister({required this.addr, this.area, this.table});
  

 final  String addr;
 final  ModbusArea? area;
 final  String? table;

/// Create a copy of PointRegister
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModbusRegisterCopyWith<ModbusRegister> get copyWith => _$ModbusRegisterCopyWithImpl<ModbusRegister>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModbusRegister&&(identical(other.addr, addr) || other.addr == addr)&&(identical(other.area, area) || other.area == area)&&(identical(other.table, table) || other.table == table));
}


@override
int get hashCode {
    return Object.hash(runtimeType,addr,area,table);
}

@override
String toString() {
    return 'PointRegister.modbus(addr: $addr, area: $area, table: $table)';
}


}

/// @nodoc
abstract mixin class $ModbusRegisterCopyWith<$Res> implements $PointRegisterCopyWith<$Res> {
  factory $ModbusRegisterCopyWith(ModbusRegister value, $Res Function(ModbusRegister) _then) = _$ModbusRegisterCopyWithImpl;
@useResult
$Res call({
 String addr, ModbusArea? area, String? table
});




}
/// @nodoc
class _$ModbusRegisterCopyWithImpl<$Res>
    implements $ModbusRegisterCopyWith<$Res> {
  _$ModbusRegisterCopyWithImpl(this._self, this._then);

  final ModbusRegister _self;
  final $Res Function(ModbusRegister) _then;

/// Create a copy of PointRegister
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? addr = null,Object? area = freezed,Object? table = freezed,}) {
  return _then(ModbusRegister(
addr: null == addr ? _self.addr : addr // ignore: cast_nullable_to_non_nullable
as String,area: freezed == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as ModbusArea?,table: freezed == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AddressRegister implements PointRegister {
  const AddressRegister(this.text);
  

 final  String text;

/// Create a copy of PointRegister
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressRegisterCopyWith<AddressRegister> get copyWith => _$AddressRegisterCopyWithImpl<AddressRegister>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressRegister&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'PointRegister.address(text: $text)';
}


}

/// @nodoc
abstract mixin class $AddressRegisterCopyWith<$Res> implements $PointRegisterCopyWith<$Res> {
  factory $AddressRegisterCopyWith(AddressRegister value, $Res Function(AddressRegister) _then) = _$AddressRegisterCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AddressRegisterCopyWithImpl<$Res>
    implements $AddressRegisterCopyWith<$Res> {
  _$AddressRegisterCopyWithImpl(this._self, this._then);

  final AddressRegister _self;
  final $Res Function(AddressRegister) _then;

/// Create a copy of PointRegister
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AddressRegister(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NoRegister implements PointRegister {
  const NoRegister();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NoRegister);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PointRegister.none()';
}


}




// dart format on
