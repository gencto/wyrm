// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'watch_group.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WatchGroup {

 String get name;/// `None`, `Interval`, `All Data`, `Point Change`.
 String get loggingType; num? get interval; num? get flush;/// The watches' node names (`w1`) and the keys they record.
 IList<String> get watchIds; IList<String> get keys;
/// Create a copy of WatchGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WatchGroupCopyWith<WatchGroup> get copyWith => _$WatchGroupCopyWithImpl<WatchGroup>(this as WatchGroup, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WatchGroup;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WatchGroup&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.loggingType, _this.loggingType) || other.loggingType == _this.loggingType)&&(identical(other.interval, _this.interval) || other.interval == _this.interval)&&(identical(other.flush, _this.flush) || other.flush == _this.flush)&&const DeepCollectionEquality().equals(other.watchIds, _this.watchIds)&&const DeepCollectionEquality().equals(other.keys, _this.keys));
}


@override
int get hashCode {
  final _this = this as WatchGroup;
  return Object.hash(runtimeType,_this.name,_this.loggingType,_this.interval,_this.flush,const DeepCollectionEquality().hash(_this.watchIds),const DeepCollectionEquality().hash(_this.keys));
}

@override
String toString() {
  final _this = this as WatchGroup;
  return 'WatchGroup(name: ${_this.name}, loggingType: ${_this.loggingType}, interval: ${_this.interval}, flush: ${_this.flush}, watchIds: ${_this.watchIds}, keys: ${_this.keys})';
}


}

/// @nodoc
abstract mixin class $WatchGroupCopyWith<$Res>  {
  factory $WatchGroupCopyWith(WatchGroup value, $Res Function(WatchGroup) _then) = _$WatchGroupCopyWithImpl;
@useResult
$Res call({
 String name, String loggingType, num? interval, num? flush, IList<String> watchIds, IList<String> keys
});




}
/// @nodoc
class _$WatchGroupCopyWithImpl<$Res>
    implements $WatchGroupCopyWith<$Res> {
  _$WatchGroupCopyWithImpl(this._self, this._then);

  final WatchGroup _self;
  final $Res Function(WatchGroup) _then;

/// Create a copy of WatchGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? loggingType = null,Object? interval = freezed,Object? flush = freezed,Object? watchIds = null,Object? keys = null,}) {
  return _then(WatchGroup(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,loggingType: null == loggingType ? _self.loggingType : loggingType // ignore: cast_nullable_to_non_nullable
as String,interval: freezed == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as num?,flush: freezed == flush ? _self.flush : flush // ignore: cast_nullable_to_non_nullable
as num?,watchIds: null == watchIds ? _self.watchIds : watchIds // ignore: cast_nullable_to_non_nullable
as IList<String>,keys: null == keys ? _self.keys : keys // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _WatchGroup implements WatchGroup {
  const _WatchGroup({required this.name, this.loggingType = '', this.interval, this.flush, this.watchIds = const IListConst([]), this.keys = const IListConst([])});
  

@override final  String name;
/// `None`, `Interval`, `All Data`, `Point Change`.
@override@JsonKey() final  String loggingType;
@override final  num? interval;
@override final  num? flush;
/// The watches' node names (`w1`) and the keys they record.
@override@JsonKey() final  IList<String> watchIds;
@override@JsonKey() final  IList<String> keys;

/// Create a copy of WatchGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WatchGroupCopyWith<_WatchGroup> get copyWith => __$WatchGroupCopyWithImpl<_WatchGroup>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WatchGroup&&(identical(other.name, name) || other.name == name)&&(identical(other.loggingType, loggingType) || other.loggingType == loggingType)&&(identical(other.interval, interval) || other.interval == interval)&&(identical(other.flush, flush) || other.flush == flush)&&const DeepCollectionEquality().equals(other.watchIds, watchIds)&&const DeepCollectionEquality().equals(other.keys, keys));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,loggingType,interval,flush,const DeepCollectionEquality().hash(watchIds),const DeepCollectionEquality().hash(keys));
}

@override
String toString() {
    return 'WatchGroup(name: $name, loggingType: $loggingType, interval: $interval, flush: $flush, watchIds: $watchIds, keys: $keys)';
}


}

/// @nodoc
abstract mixin class _$WatchGroupCopyWith<$Res> implements $WatchGroupCopyWith<$Res> {
  factory _$WatchGroupCopyWith(_WatchGroup value, $Res Function(_WatchGroup) _then) = __$WatchGroupCopyWithImpl;
@override @useResult
$Res call({
 String name, String loggingType, num? interval, num? flush, IList<String> watchIds, IList<String> keys
});




}
/// @nodoc
class __$WatchGroupCopyWithImpl<$Res>
    implements _$WatchGroupCopyWith<$Res> {
  __$WatchGroupCopyWithImpl(this._self, this._then);

  final _WatchGroup _self;
  final $Res Function(_WatchGroup) _then;

/// Create a copy of WatchGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? loggingType = null,Object? interval = freezed,Object? flush = freezed,Object? watchIds = null,Object? keys = null,}) {
  return _then(_WatchGroup(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,loggingType: null == loggingType ? _self.loggingType : loggingType // ignore: cast_nullable_to_non_nullable
as String,interval: freezed == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as num?,flush: freezed == flush ? _self.flush : flush // ignore: cast_nullable_to_non_nullable
as num?,watchIds: null == watchIds ? _self.watchIds : watchIds // ignore: cast_nullable_to_non_nullable
as IList<String>,keys: null == keys ? _self.keys : keys // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
