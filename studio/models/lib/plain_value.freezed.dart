// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plain_value.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlainValue {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlainValue()';
}


}

/// @nodoc
class $PlainValueCopyWith<$Res>  {
$PlainValueCopyWith(PlainValue _, $Res Function(PlainValue) __);
}



/// @nodoc


class PlainValueNothing extends PlainValue {
  const PlainValueNothing(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueNothing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlainValue.nothing()';
}


}




/// @nodoc


class PlainValueFlag extends PlainValue {
  const PlainValueFlag(this.value): super._();
  

 final  bool value;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueFlagCopyWith<PlainValueFlag> get copyWith => _$PlainValueFlagCopyWithImpl<PlainValueFlag>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueFlag&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'PlainValue.flag(value: $value)';
}


}

/// @nodoc
abstract mixin class $PlainValueFlagCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueFlagCopyWith(PlainValueFlag value, $Res Function(PlainValueFlag) _then) = _$PlainValueFlagCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$PlainValueFlagCopyWithImpl<$Res>
    implements $PlainValueFlagCopyWith<$Res> {
  _$PlainValueFlagCopyWithImpl(this._self, this._then);

  final PlainValueFlag _self;
  final $Res Function(PlainValueFlag) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(PlainValueFlag(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class PlainValueNumber extends PlainValue {
  const PlainValueNumber(this.value): super._();
  

 final  num value;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueNumberCopyWith<PlainValueNumber> get copyWith => _$PlainValueNumberCopyWithImpl<PlainValueNumber>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueNumber&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'PlainValue.number(value: $value)';
}


}

/// @nodoc
abstract mixin class $PlainValueNumberCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueNumberCopyWith(PlainValueNumber value, $Res Function(PlainValueNumber) _then) = _$PlainValueNumberCopyWithImpl;
@useResult
$Res call({
 num value
});




}
/// @nodoc
class _$PlainValueNumberCopyWithImpl<$Res>
    implements $PlainValueNumberCopyWith<$Res> {
  _$PlainValueNumberCopyWithImpl(this._self, this._then);

  final PlainValueNumber _self;
  final $Res Function(PlainValueNumber) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(PlainValueNumber(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as num,
  ));
}


}

/// @nodoc


class PlainValueText extends PlainValue {
  const PlainValueText(this.text): super._();
  

 final  String text;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueTextCopyWith<PlainValueText> get copyWith => _$PlainValueTextCopyWithImpl<PlainValueText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'PlainValue.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $PlainValueTextCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueTextCopyWith(PlainValueText value, $Res Function(PlainValueText) _then) = _$PlainValueTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$PlainValueTextCopyWithImpl<$Res>
    implements $PlainValueTextCopyWith<$Res> {
  _$PlainValueTextCopyWithImpl(this._self, this._then);

  final PlainValueText _self;
  final $Res Function(PlainValueText) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(PlainValueText(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PlainValueBytes extends PlainValue {
  const PlainValueBytes(this.bytes): super._();
  

 final  Uint8List bytes;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueBytesCopyWith<PlainValueBytes> get copyWith => _$PlainValueBytesCopyWithImpl<PlainValueBytes>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueBytes&&const DeepCollectionEquality().equals(other.bytes, bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes));
}

@override
String toString() {
    return 'PlainValue.bytes(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $PlainValueBytesCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueBytesCopyWith(PlainValueBytes value, $Res Function(PlainValueBytes) _then) = _$PlainValueBytesCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes
});




}
/// @nodoc
class _$PlainValueBytesCopyWithImpl<$Res>
    implements $PlainValueBytesCopyWith<$Res> {
  _$PlainValueBytesCopyWithImpl(this._self, this._then);

  final PlainValueBytes _self;
  final $Res Function(PlainValueBytes) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(PlainValueBytes(
null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class PlainValueList extends PlainValue {
  const PlainValueList({required this.items, required this.raw}): super._();
  

 final  IList<PlainValue> items;
 final  Object raw;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueListCopyWith<PlainValueList> get copyWith => _$PlainValueListCopyWithImpl<PlainValueList>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueList&&const DeepCollectionEquality().equals(other.items, items)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(items),const DeepCollectionEquality().hash(raw));
}

@override
String toString() {
    return 'PlainValue.list(items: $items, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $PlainValueListCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueListCopyWith(PlainValueList value, $Res Function(PlainValueList) _then) = _$PlainValueListCopyWithImpl;
@useResult
$Res call({
 IList<PlainValue> items, Object raw
});




}
/// @nodoc
class _$PlainValueListCopyWithImpl<$Res>
    implements $PlainValueListCopyWith<$Res> {
  _$PlainValueListCopyWithImpl(this._self, this._then);

  final PlainValueList _self;
  final $Res Function(PlainValueList) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? items = null,Object? raw = null,}) {
  return _then(PlainValueList(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as IList<PlainValue>,raw: null == raw ? _self.raw : raw ,
  ));
}


}

/// @nodoc


class PlainValueMap extends PlainValue {
  const PlainValueMap({required this.entries, required this.raw}): super._();
  

 final  IList<PlainEntry> entries;
 final  Object raw;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueMapCopyWith<PlainValueMap> get copyWith => _$PlainValueMapCopyWithImpl<PlainValueMap>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueMap&&const DeepCollectionEquality().equals(other.entries, entries)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(entries),const DeepCollectionEquality().hash(raw));
}

@override
String toString() {
    return 'PlainValue.map(entries: $entries, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $PlainValueMapCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueMapCopyWith(PlainValueMap value, $Res Function(PlainValueMap) _then) = _$PlainValueMapCopyWithImpl;
@useResult
$Res call({
 IList<PlainEntry> entries, Object raw
});




}
/// @nodoc
class _$PlainValueMapCopyWithImpl<$Res>
    implements $PlainValueMapCopyWith<$Res> {
  _$PlainValueMapCopyWithImpl(this._self, this._then);

  final PlainValueMap _self;
  final $Res Function(PlainValueMap) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entries = null,Object? raw = null,}) {
  return _then(PlainValueMap(
entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as IList<PlainEntry>,raw: null == raw ? _self.raw : raw ,
  ));
}


}

/// @nodoc


class PlainValueOther extends PlainValue {
  const PlainValueOther({required this.text, required this.type, required this.raw}): super._();
  

 final  String text;
 final  String type;
 final  Object raw;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainValueOtherCopyWith<PlainValueOther> get copyWith => _$PlainValueOtherCopyWithImpl<PlainValueOther>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainValueOther&&(identical(other.text, text) || other.text == text)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,type,const DeepCollectionEquality().hash(raw));
}

@override
String toString() {
    return 'PlainValue.other(text: $text, type: $type, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $PlainValueOtherCopyWith<$Res> implements $PlainValueCopyWith<$Res> {
  factory $PlainValueOtherCopyWith(PlainValueOther value, $Res Function(PlainValueOther) _then) = _$PlainValueOtherCopyWithImpl;
@useResult
$Res call({
 String text, String type, Object raw
});




}
/// @nodoc
class _$PlainValueOtherCopyWithImpl<$Res>
    implements $PlainValueOtherCopyWith<$Res> {
  _$PlainValueOtherCopyWithImpl(this._self, this._then);

  final PlainValueOther _self;
  final $Res Function(PlainValueOther) _then;

/// Create a copy of PlainValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,Object? type = null,Object? raw = null,}) {
  return _then(PlainValueOther(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,raw: null == raw ? _self.raw : raw ,
  ));
}


}

// dart format on
