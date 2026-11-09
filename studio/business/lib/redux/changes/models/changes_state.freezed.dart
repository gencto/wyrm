// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'changes_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChangesState {

 IMap<String, StagedChange> get table; IList<String> get view; bool get open; String? get message;
/// Create a copy of ChangesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangesStateCopyWith<ChangesState> get copyWith => _$ChangesStateCopyWithImpl<ChangesState>(this as ChangesState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.open, open) || other.open == open)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),open,message);

@override
String toString() {
  return 'ChangesState(table: $table, view: $view, open: $open, message: $message)';
}


}

/// @nodoc
abstract mixin class $ChangesStateCopyWith<$Res>  {
  factory $ChangesStateCopyWith(ChangesState value, $Res Function(ChangesState) _then) = _$ChangesStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, StagedChange> table, IList<String> view, bool open, String? message
});




}
/// @nodoc
class _$ChangesStateCopyWithImpl<$Res>
    implements $ChangesStateCopyWith<$Res> {
  _$ChangesStateCopyWithImpl(this._self, this._then);

  final ChangesState _self;
  final $Res Function(ChangesState) _then;

/// Create a copy of ChangesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? open = null,Object? message = freezed,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, StagedChange>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _ChangesState implements ChangesState {
  const _ChangesState({this.table = const IMapConst({}), this.view = const IListConst([]), this.open = false, this.message});
  

@override@JsonKey() final  IMap<String, StagedChange> table;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  bool open;
@override final  String? message;

/// Create a copy of ChangesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChangesStateCopyWith<_ChangesState> get copyWith => __$ChangesStateCopyWithImpl<_ChangesState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChangesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.open, open) || other.open == open)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),open,message);

@override
String toString() {
  return 'ChangesState(table: $table, view: $view, open: $open, message: $message)';
}


}

/// @nodoc
abstract mixin class _$ChangesStateCopyWith<$Res> implements $ChangesStateCopyWith<$Res> {
  factory _$ChangesStateCopyWith(_ChangesState value, $Res Function(_ChangesState) _then) = __$ChangesStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, StagedChange> table, IList<String> view, bool open, String? message
});




}
/// @nodoc
class __$ChangesStateCopyWithImpl<$Res>
    implements _$ChangesStateCopyWith<$Res> {
  __$ChangesStateCopyWithImpl(this._self, this._then);

  final _ChangesState _self;
  final $Res Function(_ChangesState) _then;

/// Create a copy of ChangesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? open = null,Object? message = freezed,}) {
  return _then(_ChangesState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, StagedChange>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
