// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attention_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttentionItem {

 AttentionKind get kind;/// What it is about: a link id, or the node under `sys/quarantine`.
 String get subject;/// The certificate CN of a quarantine entry (`link:field-gw`).
 String get name;/// Records behind (standby), sites relayed (broker), denials more
/// (ACL).
 int get count;/// Forks moved aside (standby); the ACL counter when last seen.
 int get more;/// When a quarantine entry was first seen.
 DateTime? get since;
/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttentionItemCopyWith<AttentionItem> get copyWith => _$AttentionItemCopyWithImpl<AttentionItem>(this as AttentionItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttentionItem&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.name, name) || other.name == name)&&(identical(other.count, count) || other.count == count)&&(identical(other.more, more) || other.more == more)&&(identical(other.since, since) || other.since == since));
}


@override
int get hashCode => Object.hash(runtimeType,kind,subject,name,count,more,since);

@override
String toString() {
  return 'AttentionItem(kind: $kind, subject: $subject, name: $name, count: $count, more: $more, since: $since)';
}


}

/// @nodoc
abstract mixin class $AttentionItemCopyWith<$Res>  {
  factory $AttentionItemCopyWith(AttentionItem value, $Res Function(AttentionItem) _then) = _$AttentionItemCopyWithImpl;
@useResult
$Res call({
 AttentionKind kind, String subject, String name, int count, int more, DateTime? since
});




}
/// @nodoc
class _$AttentionItemCopyWithImpl<$Res>
    implements $AttentionItemCopyWith<$Res> {
  _$AttentionItemCopyWithImpl(this._self, this._then);

  final AttentionItem _self;
  final $Res Function(AttentionItem) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? subject = null,Object? name = null,Object? count = null,Object? more = null,Object? since = freezed,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AttentionKind,subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,more: null == more ? _self.more : more // ignore: cast_nullable_to_non_nullable
as int,since: freezed == since ? _self.since : since // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}



/// @nodoc


class _AttentionItem implements AttentionItem {
  const _AttentionItem({required this.kind, this.subject = '', this.name = '', this.count = 0, this.more = 0, this.since});
  

@override final  AttentionKind kind;
/// What it is about: a link id, or the node under `sys/quarantine`.
@override@JsonKey() final  String subject;
/// The certificate CN of a quarantine entry (`link:field-gw`).
@override@JsonKey() final  String name;
/// Records behind (standby), sites relayed (broker), denials more
/// (ACL).
@override@JsonKey() final  int count;
/// Forks moved aside (standby); the ACL counter when last seen.
@override@JsonKey() final  int more;
/// When a quarantine entry was first seen.
@override final  DateTime? since;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttentionItemCopyWith<_AttentionItem> get copyWith => __$AttentionItemCopyWithImpl<_AttentionItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttentionItem&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.name, name) || other.name == name)&&(identical(other.count, count) || other.count == count)&&(identical(other.more, more) || other.more == more)&&(identical(other.since, since) || other.since == since));
}


@override
int get hashCode => Object.hash(runtimeType,kind,subject,name,count,more,since);

@override
String toString() {
  return 'AttentionItem(kind: $kind, subject: $subject, name: $name, count: $count, more: $more, since: $since)';
}


}

/// @nodoc
abstract mixin class _$AttentionItemCopyWith<$Res> implements $AttentionItemCopyWith<$Res> {
  factory _$AttentionItemCopyWith(_AttentionItem value, $Res Function(_AttentionItem) _then) = __$AttentionItemCopyWithImpl;
@override @useResult
$Res call({
 AttentionKind kind, String subject, String name, int count, int more, DateTime? since
});




}
/// @nodoc
class __$AttentionItemCopyWithImpl<$Res>
    implements _$AttentionItemCopyWith<$Res> {
  __$AttentionItemCopyWithImpl(this._self, this._then);

  final _AttentionItem _self;
  final $Res Function(_AttentionItem) _then;

/// Create a copy of AttentionItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? subject = null,Object? name = null,Object? count = null,Object? more = null,Object? since = freezed,}) {
  return _then(_AttentionItem(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AttentionKind,subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,more: null == more ? _self.more : more // ignore: cast_nullable_to_non_nullable
as int,since: freezed == since ? _self.since : since // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
