// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'problems_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProblemsState {

 IList<StudioError> get items; int get unread; bool get open; IList<int> get toasts; IList<StudioNotice> get notices;
/// Create a copy of ProblemsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemsStateCopyWith<ProblemsState> get copyWith => _$ProblemsStateCopyWithImpl<ProblemsState>(this as ProblemsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProblemsState&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.unread, unread) || other.unread == unread)&&(identical(other.open, open) || other.open == open)&&const DeepCollectionEquality().equals(other.toasts, toasts)&&const DeepCollectionEquality().equals(other.notices, notices));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),unread,open,const DeepCollectionEquality().hash(toasts),const DeepCollectionEquality().hash(notices));

@override
String toString() {
  return 'ProblemsState(items: $items, unread: $unread, open: $open, toasts: $toasts, notices: $notices)';
}


}

/// @nodoc
abstract mixin class $ProblemsStateCopyWith<$Res>  {
  factory $ProblemsStateCopyWith(ProblemsState value, $Res Function(ProblemsState) _then) = _$ProblemsStateCopyWithImpl;
@useResult
$Res call({
 IList<StudioError> items, int unread, bool open, IList<int> toasts, IList<StudioNotice> notices
});




}
/// @nodoc
class _$ProblemsStateCopyWithImpl<$Res>
    implements $ProblemsStateCopyWith<$Res> {
  _$ProblemsStateCopyWithImpl(this._self, this._then);

  final ProblemsState _self;
  final $Res Function(ProblemsState) _then;

/// Create a copy of ProblemsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? unread = null,Object? open = null,Object? toasts = null,Object? notices = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as IList<StudioError>,unread: null == unread ? _self.unread : unread // ignore: cast_nullable_to_non_nullable
as int,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,toasts: null == toasts ? _self.toasts : toasts // ignore: cast_nullable_to_non_nullable
as IList<int>,notices: null == notices ? _self.notices : notices // ignore: cast_nullable_to_non_nullable
as IList<StudioNotice>,
  ));
}

}



/// @nodoc


class _ProblemsState implements ProblemsState {
  const _ProblemsState({this.items = const IListConst([]), this.unread = 0, this.open = false, this.toasts = const IListConst([]), this.notices = const IListConst([])});
  

@override@JsonKey() final  IList<StudioError> items;
@override@JsonKey() final  int unread;
@override@JsonKey() final  bool open;
@override@JsonKey() final  IList<int> toasts;
@override@JsonKey() final  IList<StudioNotice> notices;

/// Create a copy of ProblemsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProblemsStateCopyWith<_ProblemsState> get copyWith => __$ProblemsStateCopyWithImpl<_ProblemsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProblemsState&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.unread, unread) || other.unread == unread)&&(identical(other.open, open) || other.open == open)&&const DeepCollectionEquality().equals(other.toasts, toasts)&&const DeepCollectionEquality().equals(other.notices, notices));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),unread,open,const DeepCollectionEquality().hash(toasts),const DeepCollectionEquality().hash(notices));

@override
String toString() {
  return 'ProblemsState(items: $items, unread: $unread, open: $open, toasts: $toasts, notices: $notices)';
}


}

/// @nodoc
abstract mixin class _$ProblemsStateCopyWith<$Res> implements $ProblemsStateCopyWith<$Res> {
  factory _$ProblemsStateCopyWith(_ProblemsState value, $Res Function(_ProblemsState) _then) = __$ProblemsStateCopyWithImpl;
@override @useResult
$Res call({
 IList<StudioError> items, int unread, bool open, IList<int> toasts, IList<StudioNotice> notices
});




}
/// @nodoc
class __$ProblemsStateCopyWithImpl<$Res>
    implements _$ProblemsStateCopyWith<$Res> {
  __$ProblemsStateCopyWithImpl(this._self, this._then);

  final _ProblemsState _self;
  final $Res Function(_ProblemsState) _then;

/// Create a copy of ProblemsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? unread = null,Object? open = null,Object? toasts = null,Object? notices = null,}) {
  return _then(_ProblemsState(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as IList<StudioError>,unread: null == unread ? _self.unread : unread // ignore: cast_nullable_to_non_nullable
as int,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,toasts: null == toasts ? _self.toasts : toasts // ignore: cast_nullable_to_non_nullable
as IList<int>,notices: null == notices ? _self.notices : notices // ignore: cast_nullable_to_non_nullable
as IList<StudioNotice>,
  ));
}


}

// dart format on
