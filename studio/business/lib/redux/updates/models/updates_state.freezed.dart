// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdatesState {

 String? get package; String get view; bool get takePoint; bool get autoRollback; bool get acceptNew; String? get asks; String? get message; int get seenAt; IList<String> get queue;
/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesStateCopyWith<UpdatesState> get copyWith => _$UpdatesStateCopyWithImpl<UpdatesState>(this as UpdatesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesState&&(identical(other.package, _this.package) || other.package == _this.package)&&(identical(other.view, _this.view) || other.view == _this.view)&&(identical(other.takePoint, _this.takePoint) || other.takePoint == _this.takePoint)&&(identical(other.autoRollback, _this.autoRollback) || other.autoRollback == _this.autoRollback)&&(identical(other.acceptNew, _this.acceptNew) || other.acceptNew == _this.acceptNew)&&(identical(other.asks, _this.asks) || other.asks == _this.asks)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.seenAt, _this.seenAt) || other.seenAt == _this.seenAt)&&const DeepCollectionEquality().equals(other.queue, _this.queue));
}


@override
int get hashCode {
  final _this = this as UpdatesState;
  return Object.hash(runtimeType,_this.package,_this.view,_this.takePoint,_this.autoRollback,_this.acceptNew,_this.asks,_this.message,_this.seenAt,const DeepCollectionEquality().hash(_this.queue));
}

@override
String toString() {
  final _this = this as UpdatesState;
  return 'UpdatesState(package: ${_this.package}, view: ${_this.view}, takePoint: ${_this.takePoint}, autoRollback: ${_this.autoRollback}, acceptNew: ${_this.acceptNew}, asks: ${_this.asks}, message: ${_this.message}, seenAt: ${_this.seenAt}, queue: ${_this.queue})';
}


}

/// @nodoc
abstract mixin class $UpdatesStateCopyWith<$Res>  {
  factory $UpdatesStateCopyWith(UpdatesState value, $Res Function(UpdatesState) _then) = _$UpdatesStateCopyWithImpl;
@useResult
$Res call({
 String? package, String view, bool takePoint, bool autoRollback, bool acceptNew, String? asks, String? message, int seenAt, IList<String> queue
});




}
/// @nodoc
class _$UpdatesStateCopyWithImpl<$Res>
    implements $UpdatesStateCopyWith<$Res> {
  _$UpdatesStateCopyWithImpl(this._self, this._then);

  final UpdatesState _self;
  final $Res Function(UpdatesState) _then;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? package = freezed,Object? view = null,Object? takePoint = null,Object? autoRollback = null,Object? acceptNew = null,Object? asks = freezed,Object? message = freezed,Object? seenAt = null,Object? queue = null,}) {
  return _then(UpdatesState(
package: freezed == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String?,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as String,takePoint: null == takePoint ? _self.takePoint : takePoint // ignore: cast_nullable_to_non_nullable
as bool,autoRollback: null == autoRollback ? _self.autoRollback : autoRollback // ignore: cast_nullable_to_non_nullable
as bool,acceptNew: null == acceptNew ? _self.acceptNew : acceptNew // ignore: cast_nullable_to_non_nullable
as bool,asks: freezed == asks ? _self.asks : asks // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,seenAt: null == seenAt ? _self.seenAt : seenAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _UpdatesState implements UpdatesState {
  const _UpdatesState({this.package, this.view = 'review', this.takePoint = true, this.autoRollback = true, this.acceptNew = false, this.asks, this.message, this.seenAt = 0, this.queue = const IListConst([])});
  

@override final  String? package;
@override@JsonKey() final  String view;
@override@JsonKey() final  bool takePoint;
@override@JsonKey() final  bool autoRollback;
@override@JsonKey() final  bool acceptNew;
@override final  String? asks;
@override final  String? message;
@override@JsonKey() final  int seenAt;
@override@JsonKey() final  IList<String> queue;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesStateCopyWith<_UpdatesState> get copyWith => __$UpdatesStateCopyWithImpl<_UpdatesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesState&&(identical(other.package, package) || other.package == package)&&(identical(other.view, view) || other.view == view)&&(identical(other.takePoint, takePoint) || other.takePoint == takePoint)&&(identical(other.autoRollback, autoRollback) || other.autoRollback == autoRollback)&&(identical(other.acceptNew, acceptNew) || other.acceptNew == acceptNew)&&(identical(other.asks, asks) || other.asks == asks)&&(identical(other.message, message) || other.message == message)&&(identical(other.seenAt, seenAt) || other.seenAt == seenAt)&&const DeepCollectionEquality().equals(other.queue, queue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,package,view,takePoint,autoRollback,acceptNew,asks,message,seenAt,const DeepCollectionEquality().hash(queue));
}

@override
String toString() {
    return 'UpdatesState(package: $package, view: $view, takePoint: $takePoint, autoRollback: $autoRollback, acceptNew: $acceptNew, asks: $asks, message: $message, seenAt: $seenAt, queue: $queue)';
}


}

/// @nodoc
abstract mixin class _$UpdatesStateCopyWith<$Res> implements $UpdatesStateCopyWith<$Res> {
  factory _$UpdatesStateCopyWith(_UpdatesState value, $Res Function(_UpdatesState) _then) = __$UpdatesStateCopyWithImpl;
@override @useResult
$Res call({
 String? package, String view, bool takePoint, bool autoRollback, bool acceptNew, String? asks, String? message, int seenAt, IList<String> queue
});




}
/// @nodoc
class __$UpdatesStateCopyWithImpl<$Res>
    implements _$UpdatesStateCopyWith<$Res> {
  __$UpdatesStateCopyWithImpl(this._self, this._then);

  final _UpdatesState _self;
  final $Res Function(_UpdatesState) _then;

/// Create a copy of UpdatesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? package = freezed,Object? view = null,Object? takePoint = null,Object? autoRollback = null,Object? acceptNew = null,Object? asks = freezed,Object? message = freezed,Object? seenAt = null,Object? queue = null,}) {
  return _then(_UpdatesState(
package: freezed == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String?,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as String,takePoint: null == takePoint ? _self.takePoint : takePoint // ignore: cast_nullable_to_non_nullable
as bool,autoRollback: null == autoRollback ? _self.autoRollback : autoRollback // ignore: cast_nullable_to_non_nullable
as bool,acceptNew: null == acceptNew ? _self.acceptNew : acceptNew // ignore: cast_nullable_to_non_nullable
as bool,asks: freezed == asks ? _self.asks : asks // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,seenAt: null == seenAt ? _self.seenAt : seenAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
