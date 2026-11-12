// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_set.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveSet {

 IList<String> get values; IList<String> get lists;
/// Create a copy of LiveSet
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveSetCopyWith<LiveSet> get copyWith => _$LiveSetCopyWithImpl<LiveSet>(this as LiveSet, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LiveSet;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveSet&&const DeepCollectionEquality().equals(other.values, _this.values)&&const DeepCollectionEquality().equals(other.lists, _this.lists));
}


@override
int get hashCode {
  final _this = this as LiveSet;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.values),const DeepCollectionEquality().hash(_this.lists));
}

@override
String toString() {
  final _this = this as LiveSet;
  return 'LiveSet(values: ${_this.values}, lists: ${_this.lists})';
}


}

/// @nodoc
abstract mixin class $LiveSetCopyWith<$Res>  {
  factory $LiveSetCopyWith(LiveSet value, $Res Function(LiveSet) _then) = _$LiveSetCopyWithImpl;
@useResult
$Res call({
 IList<String> values, IList<String> lists
});




}
/// @nodoc
class _$LiveSetCopyWithImpl<$Res>
    implements $LiveSetCopyWith<$Res> {
  _$LiveSetCopyWithImpl(this._self, this._then);

  final LiveSet _self;
  final $Res Function(LiveSet) _then;

/// Create a copy of LiveSet
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? values = null,Object? lists = null,}) {
  return _then(LiveSet(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IList<String>,lists: null == lists ? _self.lists : lists // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _LiveSet implements LiveSet {
  const _LiveSet({this.values = const IListConst([]), this.lists = const IListConst([])});
  

@override@JsonKey() final  IList<String> values;
@override@JsonKey() final  IList<String> lists;

/// Create a copy of LiveSet
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveSetCopyWith<_LiveSet> get copyWith => __$LiveSetCopyWithImpl<_LiveSet>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveSet&&const DeepCollectionEquality().equals(other.values, values)&&const DeepCollectionEquality().equals(other.lists, lists));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(values),const DeepCollectionEquality().hash(lists));
}

@override
String toString() {
    return 'LiveSet(values: $values, lists: $lists)';
}


}

/// @nodoc
abstract mixin class _$LiveSetCopyWith<$Res> implements $LiveSetCopyWith<$Res> {
  factory _$LiveSetCopyWith(_LiveSet value, $Res Function(_LiveSet) _then) = __$LiveSetCopyWithImpl;
@override @useResult
$Res call({
 IList<String> values, IList<String> lists
});




}
/// @nodoc
class __$LiveSetCopyWithImpl<$Res>
    implements _$LiveSetCopyWith<$Res> {
  __$LiveSetCopyWithImpl(this._self, this._then);

  final _LiveSet _self;
  final $Res Function(_LiveSet) _then;

/// Create a copy of LiveSet
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? values = null,Object? lists = null,}) {
  return _then(_LiveSet(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IList<String>,lists: null == lists ? _self.lists : lists // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
