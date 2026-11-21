// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quarantine_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuarantineEntry {

 String get cn;/// The node under `sys/quarantine` (the CN made a key segment).
 String get node;
/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineEntryCopyWith<QuarantineEntry> get copyWith => _$QuarantineEntryCopyWithImpl<QuarantineEntry>(this as QuarantineEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuarantineEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineEntry&&(identical(other.cn, _this.cn) || other.cn == _this.cn)&&(identical(other.node, _this.node) || other.node == _this.node));
}


@override
int get hashCode {
  final _this = this as QuarantineEntry;
  return Object.hash(runtimeType,_this.cn,_this.node);
}

@override
String toString() {
  final _this = this as QuarantineEntry;
  return 'QuarantineEntry(cn: ${_this.cn}, node: ${_this.node})';
}


}

/// @nodoc
abstract mixin class $QuarantineEntryCopyWith<$Res>  {
  factory $QuarantineEntryCopyWith(QuarantineEntry value, $Res Function(QuarantineEntry) _then) = _$QuarantineEntryCopyWithImpl;
@useResult
$Res call({
 String cn, String node
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
@pragma('vm:prefer-inline') @override $Res call({Object? cn = null,Object? node = null,}) {
  return _then(_self.copyWith(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class QuarantineLink extends QuarantineEntry {
  const QuarantineLink({required this.cn, required this.node, this.from, this.firstSeen, this.deauthorized = false}): super._();
  

@override final  String cn;
/// The node under `sys/quarantine` (the CN made a key segment).
@override final  String node;
 final  String? from;
 final  DateTime? firstSeen;
@JsonKey() final  bool deauthorized;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineLinkCopyWith<QuarantineLink> get copyWith => _$QuarantineLinkCopyWithImpl<QuarantineLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineLink&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.node, node) || other.node == node)&&(identical(other.from, from) || other.from == from)&&(identical(other.firstSeen, firstSeen) || other.firstSeen == firstSeen)&&(identical(other.deauthorized, deauthorized) || other.deauthorized == deauthorized));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cn,node,from,firstSeen,deauthorized);
}

@override
String toString() {
    return 'QuarantineEntry.link(cn: $cn, node: $node, from: $from, firstSeen: $firstSeen, deauthorized: $deauthorized)';
}


}

/// @nodoc
abstract mixin class $QuarantineLinkCopyWith<$Res> implements $QuarantineEntryCopyWith<$Res> {
  factory $QuarantineLinkCopyWith(QuarantineLink value, $Res Function(QuarantineLink) _then) = _$QuarantineLinkCopyWithImpl;
@override @useResult
$Res call({
 String cn, String node, String? from, DateTime? firstSeen, bool deauthorized
});




}
/// @nodoc
class _$QuarantineLinkCopyWithImpl<$Res>
    implements $QuarantineLinkCopyWith<$Res> {
  _$QuarantineLinkCopyWithImpl(this._self, this._then);

  final QuarantineLink _self;
  final $Res Function(QuarantineLink) _then;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cn = null,Object? node = null,Object? from = freezed,Object? firstSeen = freezed,Object? deauthorized = null,}) {
  return _then(QuarantineLink(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,firstSeen: freezed == firstSeen ? _self.firstSeen : firstSeen // ignore: cast_nullable_to_non_nullable
as DateTime?,deauthorized: null == deauthorized ? _self.deauthorized : deauthorized // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class QuarantineBroker extends QuarantineEntry {
  const QuarantineBroker({required this.cn, required this.node, this.from, this.firstSeen, this.via = const IListConst([]), this.key, this.deauthorized = false}): super._();
  

@override final  String cn;
@override final  String node;
 final  String? from;
 final  DateTime? firstSeen;
@JsonKey() final  IList<String> via;
 final  String? key;
@JsonKey() final  bool deauthorized;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineBrokerCopyWith<QuarantineBroker> get copyWith => _$QuarantineBrokerCopyWithImpl<QuarantineBroker>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineBroker&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.node, node) || other.node == node)&&(identical(other.from, from) || other.from == from)&&(identical(other.firstSeen, firstSeen) || other.firstSeen == firstSeen)&&const DeepCollectionEquality().equals(other.via, via)&&(identical(other.key, key) || other.key == key)&&(identical(other.deauthorized, deauthorized) || other.deauthorized == deauthorized));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cn,node,from,firstSeen,const DeepCollectionEquality().hash(via),key,deauthorized);
}

@override
String toString() {
    return 'QuarantineEntry.broker(cn: $cn, node: $node, from: $from, firstSeen: $firstSeen, via: $via, key: $key, deauthorized: $deauthorized)';
}


}

/// @nodoc
abstract mixin class $QuarantineBrokerCopyWith<$Res> implements $QuarantineEntryCopyWith<$Res> {
  factory $QuarantineBrokerCopyWith(QuarantineBroker value, $Res Function(QuarantineBroker) _then) = _$QuarantineBrokerCopyWithImpl;
@override @useResult
$Res call({
 String cn, String node, String? from, DateTime? firstSeen, IList<String> via, String? key, bool deauthorized
});




}
/// @nodoc
class _$QuarantineBrokerCopyWithImpl<$Res>
    implements $QuarantineBrokerCopyWith<$Res> {
  _$QuarantineBrokerCopyWithImpl(this._self, this._then);

  final QuarantineBroker _self;
  final $Res Function(QuarantineBroker) _then;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cn = null,Object? node = null,Object? from = freezed,Object? firstSeen = freezed,Object? via = null,Object? key = freezed,Object? deauthorized = null,}) {
  return _then(QuarantineBroker(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
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


class QuarantineNotRead extends QuarantineEntry {
  const QuarantineNotRead({required this.cn, required this.node}): super._();
  

@override final  String cn;
@override final  String node;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineNotReadCopyWith<QuarantineNotRead> get copyWith => _$QuarantineNotReadCopyWithImpl<QuarantineNotRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineNotRead&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.node, node) || other.node == node));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cn,node);
}

@override
String toString() {
    return 'QuarantineEntry.notRead(cn: $cn, node: $node)';
}


}

/// @nodoc
abstract mixin class $QuarantineNotReadCopyWith<$Res> implements $QuarantineEntryCopyWith<$Res> {
  factory $QuarantineNotReadCopyWith(QuarantineNotRead value, $Res Function(QuarantineNotRead) _then) = _$QuarantineNotReadCopyWithImpl;
@override @useResult
$Res call({
 String cn, String node
});




}
/// @nodoc
class _$QuarantineNotReadCopyWithImpl<$Res>
    implements $QuarantineNotReadCopyWith<$Res> {
  _$QuarantineNotReadCopyWithImpl(this._self, this._then);

  final QuarantineNotRead _self;
  final $Res Function(QuarantineNotRead) _then;

/// Create a copy of QuarantineEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cn = null,Object? node = null,}) {
  return _then(QuarantineNotRead(
cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
