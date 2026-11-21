// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attention_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttentionItem {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionItem);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AttentionItem()';
}


}

/// @nodoc
class $AttentionItemCopyWith<$Res>  {
$AttentionItemCopyWith(AttentionItem _, $Res Function(AttentionItem) __);
}



/// @nodoc


class AttentionStandbyBehind implements AttentionItem {
  const AttentionStandbyBehind({required this.lag, required this.forks});
  

 final  int lag;
 final  int forks;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionStandbyBehindCopyWith<AttentionStandbyBehind> get copyWith => _$AttentionStandbyBehindCopyWithImpl<AttentionStandbyBehind>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionStandbyBehind&&(identical(other.lag, lag) || other.lag == lag)&&(identical(other.forks, forks) || other.forks == forks));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lag,forks);
}

@override
String toString() {
    return 'AttentionItem.standbyBehind(lag: $lag, forks: $forks)';
}


}

/// @nodoc
abstract mixin class $AttentionStandbyBehindCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionStandbyBehindCopyWith(AttentionStandbyBehind value, $Res Function(AttentionStandbyBehind) _then) = _$AttentionStandbyBehindCopyWithImpl;
@useResult
$Res call({
 int lag, int forks
});




}
/// @nodoc
class _$AttentionStandbyBehindCopyWithImpl<$Res>
    implements $AttentionStandbyBehindCopyWith<$Res> {
  _$AttentionStandbyBehindCopyWithImpl(this._self, this._then);

  final AttentionStandbyBehind _self;
  final $Res Function(AttentionStandbyBehind) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lag = null,Object? forks = null,}) {
  return _then(AttentionStandbyBehind(
lag: null == lag ? _self.lag : lag // ignore: cast_nullable_to_non_nullable
as int,forks: null == forks ? _self.forks : forks // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AttentionLinkFailed implements AttentionItem {
  const AttentionLinkFailed({required this.link});
  

 final  String link;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionLinkFailedCopyWith<AttentionLinkFailed> get copyWith => _$AttentionLinkFailedCopyWithImpl<AttentionLinkFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionLinkFailed&&(identical(other.link, link) || other.link == link));
}


@override
int get hashCode {
    return Object.hash(runtimeType,link);
}

@override
String toString() {
    return 'AttentionItem.linkFailed(link: $link)';
}


}

/// @nodoc
abstract mixin class $AttentionLinkFailedCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionLinkFailedCopyWith(AttentionLinkFailed value, $Res Function(AttentionLinkFailed) _then) = _$AttentionLinkFailedCopyWithImpl;
@useResult
$Res call({
 String link
});




}
/// @nodoc
class _$AttentionLinkFailedCopyWithImpl<$Res>
    implements $AttentionLinkFailedCopyWith<$Res> {
  _$AttentionLinkFailedCopyWithImpl(this._self, this._then);

  final AttentionLinkFailed _self;
  final $Res Function(AttentionLinkFailed) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? link = null,}) {
  return _then(AttentionLinkFailed(
link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AttentionQuarantine implements AttentionItem {
  const AttentionQuarantine({required this.node, required this.cn, this.since});
  

 final  String node;
 final  String cn;
 final  DateTime? since;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionQuarantineCopyWith<AttentionQuarantine> get copyWith => _$AttentionQuarantineCopyWithImpl<AttentionQuarantine>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionQuarantine&&(identical(other.node, node) || other.node == node)&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.since, since) || other.since == since));
}


@override
int get hashCode {
    return Object.hash(runtimeType,node,cn,since);
}

@override
String toString() {
    return 'AttentionItem.quarantine(node: $node, cn: $cn, since: $since)';
}


}

/// @nodoc
abstract mixin class $AttentionQuarantineCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionQuarantineCopyWith(AttentionQuarantine value, $Res Function(AttentionQuarantine) _then) = _$AttentionQuarantineCopyWithImpl;
@useResult
$Res call({
 String node, String cn, DateTime? since
});




}
/// @nodoc
class _$AttentionQuarantineCopyWithImpl<$Res>
    implements $AttentionQuarantineCopyWith<$Res> {
  _$AttentionQuarantineCopyWithImpl(this._self, this._then);

  final AttentionQuarantine _self;
  final $Res Function(AttentionQuarantine) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? node = null,Object? cn = null,Object? since = freezed,}) {
  return _then(AttentionQuarantine(
node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,since: freezed == since ? _self.since : since // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class AttentionBrokerWaiting implements AttentionItem {
  const AttentionBrokerWaiting({required this.node, required this.cn, required this.relays});
  

 final  String node;
 final  String cn;
 final  int relays;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionBrokerWaitingCopyWith<AttentionBrokerWaiting> get copyWith => _$AttentionBrokerWaitingCopyWithImpl<AttentionBrokerWaiting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionBrokerWaiting&&(identical(other.node, node) || other.node == node)&&(identical(other.cn, cn) || other.cn == cn)&&(identical(other.relays, relays) || other.relays == relays));
}


@override
int get hashCode {
    return Object.hash(runtimeType,node,cn,relays);
}

@override
String toString() {
    return 'AttentionItem.brokerWaiting(node: $node, cn: $cn, relays: $relays)';
}


}

/// @nodoc
abstract mixin class $AttentionBrokerWaitingCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionBrokerWaitingCopyWith(AttentionBrokerWaiting value, $Res Function(AttentionBrokerWaiting) _then) = _$AttentionBrokerWaitingCopyWithImpl;
@useResult
$Res call({
 String node, String cn, int relays
});




}
/// @nodoc
class _$AttentionBrokerWaitingCopyWithImpl<$Res>
    implements $AttentionBrokerWaitingCopyWith<$Res> {
  _$AttentionBrokerWaitingCopyWithImpl(this._self, this._then);

  final AttentionBrokerWaiting _self;
  final $Res Function(AttentionBrokerWaiting) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? node = null,Object? cn = null,Object? relays = null,}) {
  return _then(AttentionBrokerWaiting(
node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,relays: null == relays ? _self.relays : relays // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AttentionWaitingNotRead implements AttentionItem {
  const AttentionWaitingNotRead({required this.node, required this.cn});
  

 final  String node;
 final  String cn;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionWaitingNotReadCopyWith<AttentionWaitingNotRead> get copyWith => _$AttentionWaitingNotReadCopyWithImpl<AttentionWaitingNotRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionWaitingNotRead&&(identical(other.node, node) || other.node == node)&&(identical(other.cn, cn) || other.cn == cn));
}


@override
int get hashCode {
    return Object.hash(runtimeType,node,cn);
}

@override
String toString() {
    return 'AttentionItem.waitingNotRead(node: $node, cn: $cn)';
}


}

/// @nodoc
abstract mixin class $AttentionWaitingNotReadCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionWaitingNotReadCopyWith(AttentionWaitingNotRead value, $Res Function(AttentionWaitingNotRead) _then) = _$AttentionWaitingNotReadCopyWithImpl;
@useResult
$Res call({
 String node, String cn
});




}
/// @nodoc
class _$AttentionWaitingNotReadCopyWithImpl<$Res>
    implements $AttentionWaitingNotReadCopyWith<$Res> {
  _$AttentionWaitingNotReadCopyWithImpl(this._self, this._then);

  final AttentionWaitingNotRead _self;
  final $Res Function(AttentionWaitingNotRead) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? node = null,Object? cn = null,}) {
  return _then(AttentionWaitingNotRead(
node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,cn: null == cn ? _self.cn : cn // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AttentionAclGrown implements AttentionItem {
  const AttentionAclGrown({required this.grown, required this.seen});
  

 final  int grown;
 final  int seen;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionAclGrownCopyWith<AttentionAclGrown> get copyWith => _$AttentionAclGrownCopyWithImpl<AttentionAclGrown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionAclGrown&&(identical(other.grown, grown) || other.grown == grown)&&(identical(other.seen, seen) || other.seen == seen));
}


@override
int get hashCode {
    return Object.hash(runtimeType,grown,seen);
}

@override
String toString() {
    return 'AttentionItem.aclGrown(grown: $grown, seen: $seen)';
}


}

/// @nodoc
abstract mixin class $AttentionAclGrownCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory $AttentionAclGrownCopyWith(AttentionAclGrown value, $Res Function(AttentionAclGrown) _then) = _$AttentionAclGrownCopyWithImpl;
@useResult
$Res call({
 int grown, int seen
});




}
/// @nodoc
class _$AttentionAclGrownCopyWithImpl<$Res>
    implements $AttentionAclGrownCopyWith<$Res> {
  _$AttentionAclGrownCopyWithImpl(this._self, this._then);

  final AttentionAclGrown _self;
  final $Res Function(AttentionAclGrown) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? grown = null,Object? seen = null,}) {
  return _then(AttentionAclGrown(
grown: null == grown ? _self.grown : grown // ignore: cast_nullable_to_non_nullable
as int,seen: null == seen ? _self.seen : seen // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AttentionNoStandby implements AttentionItem {
  const AttentionNoStandby();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionNoStandby);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AttentionItem.noStandby()';
}


}




// dart format on
