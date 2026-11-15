// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'requested_right.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RequestedRight {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestedRight);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RequestedRight()';
}


}

/// @nodoc
class $RequestedRightCopyWith<$Res>  {
$RequestedRightCopyWith(RequestedRight _, $Res Function(RequestedRight) __);
}



/// @nodoc


class RightNetwork implements RequestedRight {
  const RightNetwork( List<String> hosts): _hosts = hosts;
  

 final  List<String> _hosts;
 List<String> get hosts {
  if (_hosts is EqualUnmodifiableListView) return _hosts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_hosts);
}


/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RightNetworkCopyWith<RightNetwork> get copyWith => _$RightNetworkCopyWithImpl<RightNetwork>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RightNetwork&&const DeepCollectionEquality().equals(other.hosts, _hosts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_hosts));
}

@override
String toString() {
    return 'RequestedRight.network(hosts: $hosts)';
}


}

/// @nodoc
abstract mixin class $RightNetworkCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory $RightNetworkCopyWith(RightNetwork value, $Res Function(RightNetwork) _then) = _$RightNetworkCopyWithImpl;
@useResult
$Res call({
 List<String> hosts
});




}
/// @nodoc
class _$RightNetworkCopyWithImpl<$Res>
    implements $RightNetworkCopyWith<$Res> {
  _$RightNetworkCopyWithImpl(this._self, this._then);

  final RightNetwork _self;
  final $Res Function(RightNetwork) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hosts = null,}) {
  return _then(RightNetwork(
null == hosts ? _self._hosts : hosts // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class RightStore implements RequestedRight {
  const RightStore(this.mib);
  

 final  int mib;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RightStoreCopyWith<RightStore> get copyWith => _$RightStoreCopyWithImpl<RightStore>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RightStore&&(identical(other.mib, mib) || other.mib == mib));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mib);
}

@override
String toString() {
    return 'RequestedRight.store(mib: $mib)';
}


}

/// @nodoc
abstract mixin class $RightStoreCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory $RightStoreCopyWith(RightStore value, $Res Function(RightStore) _then) = _$RightStoreCopyWithImpl;
@useResult
$Res call({
 int mib
});




}
/// @nodoc
class _$RightStoreCopyWithImpl<$Res>
    implements $RightStoreCopyWith<$Res> {
  _$RightStoreCopyWithImpl(this._self, this._then);

  final RightStore _self;
  final $Res Function(RightStore) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mib = null,}) {
  return _then(RightStore(
null == mib ? _self.mib : mib // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RightMemory implements RequestedRight {
  const RightMemory(this.mib);
  

 final  int mib;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RightMemoryCopyWith<RightMemory> get copyWith => _$RightMemoryCopyWithImpl<RightMemory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RightMemory&&(identical(other.mib, mib) || other.mib == mib));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mib);
}

@override
String toString() {
    return 'RequestedRight.memory(mib: $mib)';
}


}

/// @nodoc
abstract mixin class $RightMemoryCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory $RightMemoryCopyWith(RightMemory value, $Res Function(RightMemory) _then) = _$RightMemoryCopyWithImpl;
@useResult
$Res call({
 int mib
});




}
/// @nodoc
class _$RightMemoryCopyWithImpl<$Res>
    implements $RightMemoryCopyWith<$Res> {
  _$RightMemoryCopyWithImpl(this._self, this._then);

  final RightMemory _self;
  final $Res Function(RightMemory) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mib = null,}) {
  return _then(RightMemory(
null == mib ? _self.mib : mib // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RightCall implements RequestedRight {
  const RightCall(this.ms);
  

 final  int ms;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RightCallCopyWith<RightCall> get copyWith => _$RightCallCopyWithImpl<RightCall>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RightCall&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ms);
}

@override
String toString() {
    return 'RequestedRight.call(ms: $ms)';
}


}

/// @nodoc
abstract mixin class $RightCallCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory $RightCallCopyWith(RightCall value, $Res Function(RightCall) _then) = _$RightCallCopyWithImpl;
@useResult
$Res call({
 int ms
});




}
/// @nodoc
class _$RightCallCopyWithImpl<$Res>
    implements $RightCallCopyWith<$Res> {
  _$RightCallCopyWithImpl(this._self, this._then);

  final RightCall _self;
  final $Res Function(RightCall) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ms = null,}) {
  return _then(RightCall(
null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RightGrant implements RequestedRight {
  const RightGrant({required this.level, required this.path});
  

 final  Perm level;
 final  String path;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RightGrantCopyWith<RightGrant> get copyWith => _$RightGrantCopyWithImpl<RightGrant>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RightGrant&&(identical(other.level, level) || other.level == level)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,path);
}

@override
String toString() {
    return 'RequestedRight.grant(level: $level, path: $path)';
}


}

/// @nodoc
abstract mixin class $RightGrantCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory $RightGrantCopyWith(RightGrant value, $Res Function(RightGrant) _then) = _$RightGrantCopyWithImpl;
@useResult
$Res call({
 Perm level, String path
});




}
/// @nodoc
class _$RightGrantCopyWithImpl<$Res>
    implements $RightGrantCopyWith<$Res> {
  _$RightGrantCopyWithImpl(this._self, this._then);

  final RightGrant _self;
  final $Res Function(RightGrant) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,Object? path = null,}) {
  return _then(RightGrant(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
