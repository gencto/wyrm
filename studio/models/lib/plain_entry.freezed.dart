// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plain_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlainEntry {

/// The key as text (a key of the wire may be a number: `1`).
 String get key;/// The key was a text (JSON holds only those).
 bool get textKey; PlainValue get value;
/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlainEntryCopyWith<PlainEntry> get copyWith => _$PlainEntryCopyWithImpl<PlainEntry>(this as PlainEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlainEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlainEntry&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.textKey, _this.textKey) || other.textKey == _this.textKey)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PlainEntry;
  return Object.hash(runtimeType,_this.key,_this.textKey,_this.value);
}

@override
String toString() {
  final _this = this as PlainEntry;
  return 'PlainEntry(key: ${_this.key}, textKey: ${_this.textKey}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $PlainEntryCopyWith<$Res>  {
  factory $PlainEntryCopyWith(PlainEntry value, $Res Function(PlainEntry) _then) = _$PlainEntryCopyWithImpl;
@useResult
$Res call({
 String key, bool textKey, PlainValue value
});


$PlainValueCopyWith<$Res> get value;

}
/// @nodoc
class _$PlainEntryCopyWithImpl<$Res>
    implements $PlainEntryCopyWith<$Res> {
  _$PlainEntryCopyWithImpl(this._self, this._then);

  final PlainEntry _self;
  final $Res Function(PlainEntry) _then;

/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? textKey = null,Object? value = null,}) {
  return _then(PlainEntry(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,textKey: null == textKey ? _self.textKey : textKey // ignore: cast_nullable_to_non_nullable
as bool,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlainValue,
  ));
}
/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlainValueCopyWith<$Res> get value {
  
  return $PlainValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}



/// @nodoc


class _PlainEntry implements PlainEntry {
  const _PlainEntry({required this.key, required this.textKey, required this.value});
  

/// The key as text (a key of the wire may be a number: `1`).
@override final  String key;
/// The key was a text (JSON holds only those).
@override final  bool textKey;
@override final  PlainValue value;

/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlainEntryCopyWith<_PlainEntry> get copyWith => __$PlainEntryCopyWithImpl<_PlainEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlainEntry&&(identical(other.key, key) || other.key == key)&&(identical(other.textKey, textKey) || other.textKey == textKey)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,textKey,value);
}

@override
String toString() {
    return 'PlainEntry(key: $key, textKey: $textKey, value: $value)';
}


}

/// @nodoc
abstract mixin class _$PlainEntryCopyWith<$Res> implements $PlainEntryCopyWith<$Res> {
  factory _$PlainEntryCopyWith(_PlainEntry value, $Res Function(_PlainEntry) _then) = __$PlainEntryCopyWithImpl;
@override @useResult
$Res call({
 String key, bool textKey, PlainValue value
});


@override $PlainValueCopyWith<$Res> get value;

}
/// @nodoc
class __$PlainEntryCopyWithImpl<$Res>
    implements _$PlainEntryCopyWith<$Res> {
  __$PlainEntryCopyWithImpl(this._self, this._then);

  final _PlainEntry _self;
  final $Res Function(_PlainEntry) _then;

/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? textKey = null,Object? value = null,}) {
  return _then(_PlainEntry(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,textKey: null == textKey ? _self.textKey : textKey // ignore: cast_nullable_to_non_nullable
as bool,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlainValue,
  ));
}

/// Create a copy of PlainEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlainValueCopyWith<$Res> get value {
  
  return $PlainValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
