// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'undo_tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UndoTag {

 UndoKind get kind;/// The block the edit changed; empty for a nudge.
 String get block;/// The parameter or the operand port it typed into.
 String get name;
/// Create a copy of UndoTag
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UndoTagCopyWith<UndoTag> get copyWith => _$UndoTagCopyWithImpl<UndoTag>(this as UndoTag, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UndoTag;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UndoTag&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.block, _this.block) || other.block == _this.block)&&(identical(other.name, _this.name) || other.name == _this.name));
}


@override
int get hashCode {
  final _this = this as UndoTag;
  return Object.hash(runtimeType,_this.kind,_this.block,_this.name);
}

@override
String toString() {
  final _this = this as UndoTag;
  return 'UndoTag(kind: ${_this.kind}, block: ${_this.block}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $UndoTagCopyWith<$Res>  {
  factory $UndoTagCopyWith(UndoTag value, $Res Function(UndoTag) _then) = _$UndoTagCopyWithImpl;
@useResult
$Res call({
 UndoKind kind, String block, String name
});




}
/// @nodoc
class _$UndoTagCopyWithImpl<$Res>
    implements $UndoTagCopyWith<$Res> {
  _$UndoTagCopyWithImpl(this._self, this._then);

  final UndoTag _self;
  final $Res Function(UndoTag) _then;

/// Create a copy of UndoTag
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? block = null,Object? name = null,}) {
  return _then(UndoTag(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as UndoKind,block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _UndoTag implements UndoTag {
  const _UndoTag(this.kind, {this.block = '', this.name = ''});
  

@override final  UndoKind kind;
/// The block the edit changed; empty for a nudge.
@override@JsonKey() final  String block;
/// The parameter or the operand port it typed into.
@override@JsonKey() final  String name;

/// Create a copy of UndoTag
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UndoTagCopyWith<_UndoTag> get copyWith => __$UndoTagCopyWithImpl<_UndoTag>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UndoTag&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.block, block) || other.block == block)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,block,name);
}

@override
String toString() {
    return 'UndoTag(kind: $kind, block: $block, name: $name)';
}


}

/// @nodoc
abstract mixin class _$UndoTagCopyWith<$Res> implements $UndoTagCopyWith<$Res> {
  factory _$UndoTagCopyWith(_UndoTag value, $Res Function(_UndoTag) _then) = __$UndoTagCopyWithImpl;
@override @useResult
$Res call({
 UndoKind kind, String block, String name
});




}
/// @nodoc
class __$UndoTagCopyWithImpl<$Res>
    implements _$UndoTagCopyWith<$Res> {
  __$UndoTagCopyWithImpl(this._self, this._then);

  final _UndoTag _self;
  final $Res Function(_UndoTag) _then;

/// Create a copy of UndoTag
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? block = null,Object? name = null,}) {
  return _then(_UndoTag(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as UndoKind,block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
