// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quarantine_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuarantineEntry {

 String get cn;/// `link` or `broker`.
 String get kind; String? get from; DateTime? get firstSeen; IList<String> get via;/// The broker key hash to compare (kind broker).
 String? get key; bool get deauthorized;
/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineEntryCopyWith<QuarantineEntry> get copyWith => _$QuarantineEntryCopyWithImpl<QuarantineEntry>(this as QuarantineEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineEntry&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.from, from) || other.from == from)&&(identical(other.firstSeen, firstSeen) || other.firstSeen == firstSeen)&&const DeepCollectionEquality().equals(other.via, via)&&(identical(other.key, key) || other.key == key)&&(identical(other.deauthorized, deauthorized) || other.deauthorized == deauthorized));
}


@override
int get hashCode => Object.hash(runtimeType,cn,kind,from,firstSeen,const DeepCollectionEquality().hash(via),key,deauthorized);

@override
String toString() {
  return 'QuarantineEntry(cn: $cn, kind: $kind, from: $from, firstSeen: $firstSeen, via: $via, key: $key, deauthorized: $deauthorized)';
}


}

/// @nodoc
abstract mixin class $QuarantineEntryCopyWith<$Res>  {
  factory $QuarantineEntryCopyWith(QuarantineEntry value, $Res Function(QuarantineEntry) _then) = _$QuarantineEntryCopyWithImpl;
@useResult
$Res call({
 String cn, String kind, String? from, DateTime? firstSeen, IList<String> via, String? key, bool deauthorized
});




}
/// @nodoc
class _$QuarantineEntryCopyWithImpl<$Res>
    implements $QuarantineEntryCopyWith<$Res> {
  _$QuarantineEntryCopyWithImpl(this._self, this._then);

  final QuarantineEntry _self;
  final $Res Function(QuarantineEntry) _then;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cn = null,Object? kind = null,Object? from = freezed,Object? firstSeen = freezed,Object? via = null,Object? key = freezed,Object? deauthorized = null,}) {
  return _then(_self.copyWith(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,firstSeen: freezed == firstSeen ? _self.firstSeen : firstSeen // ignore: cast_nullable_to_non_nullable
as DateTime?,via: null == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as IList<String>,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,deauthorized: null == deauthorized ? _self.deauthorized : deauthorized // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _QuarantineEntry implements QuarantineEntry {
  const _QuarantineEntry({required this.cn, this.kind = 'link', this.from, this.firstSeen, this.via = const IListConst([]), this.key, this.deauthorized = false});
  

@override final  String cn;
/// `link` or `broker`.
@override@JsonKey() final  String kind;
@override final  String? from;
@override final  DateTime? firstSeen;
@override@JsonKey() final  IList<String> via;
/// The broker key hash to compare (kind broker).
@override final  String? key;
@override@JsonKey() final  bool deauthorized;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuarantineEntryCopyWith<_QuarantineEntry> get copyWith => __$QuarantineEntryCopyWithImpl<_QuarantineEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuarantineEntry&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.from, from) || other.from == from)&&(identical(other.firstSeen, firstSeen) || other.firstSeen == firstSeen)&&const DeepCollectionEquality().equals(other.via, via)&&(identical(other.key, key) || other.key == key)&&(identical(other.deauthorized, deauthorized) || other.deauthorized == deauthorized));
}


@override
int get hashCode => Object.hash(runtimeType,cn,kind,from,firstSeen,const DeepCollectionEquality().hash(via),key,deauthorized);

@override
String toString() {
  return 'QuarantineEntry(cn: $cn, kind: $kind, from: $from, firstSeen: $firstSeen, via: $via, key: $key, deauthorized: $deauthorized)';
}


}

/// @nodoc
abstract mixin class _$QuarantineEntryCopyWith<$Res> implements $QuarantineEntryCopyWith<$Res> {
  factory _$QuarantineEntryCopyWith(_QuarantineEntry value, $Res Function(_QuarantineEntry) _then) = __$QuarantineEntryCopyWithImpl;
@override @useResult
$Res call({
 String cn, String kind, String? from, DateTime? firstSeen, IList<String> via, String? key, bool deauthorized
});




}
/// @nodoc
class __$QuarantineEntryCopyWithImpl<$Res>
    implements _$QuarantineEntryCopyWith<$Res> {
  __$QuarantineEntryCopyWithImpl(this._self, this._then);

  final _QuarantineEntry _self;
  final $Res Function(_QuarantineEntry) _then;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cn = null,Object? kind = null,Object? from = freezed,Object? firstSeen = freezed,Object? via = null,Object? key = freezed,Object? deauthorized = null,}) {
  return _then(_QuarantineEntry(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,firstSeen: freezed == firstSeen ? _self.firstSeen : firstSeen // ignore: cast_nullable_to_non_nullable
as DateTime?,via: null == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as IList<String>,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,deauthorized: null == deauthorized ? _self.deauthorized : deauthorized // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
