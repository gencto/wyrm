// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'peers_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PeersState {

 IMap<String, Peer> get table; IList<String> get view; String? get selectedPeer;
/// Create a copy of PeersState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PeersStateCopyWith<PeersState> get copyWith => _$PeersStateCopyWithImpl<PeersState>(this as PeersState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PeersState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedPeer, selectedPeer) || other.selectedPeer == selectedPeer));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedPeer);

@override
String toString() {
  return 'PeersState(table: $table, view: $view, selectedPeer: $selectedPeer)';
}


}

/// @nodoc
abstract mixin class $PeersStateCopyWith<$Res>  {
  factory $PeersStateCopyWith(PeersState value, $Res Function(PeersState) _then) = _$PeersStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, Peer> table, IList<String> view, String? selectedPeer
});




}
/// @nodoc
class _$PeersStateCopyWithImpl<$Res>
    implements $PeersStateCopyWith<$Res> {
  _$PeersStateCopyWithImpl(this._self, this._then);

  final PeersState _self;
  final $Res Function(PeersState) _then;

/// Create a copy of PeersState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? selectedPeer = freezed,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, Peer>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedPeer: freezed == selectedPeer ? _self.selectedPeer : selectedPeer // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _PeersState implements PeersState {
  const _PeersState({this.table = const IMapConst({}), this.view = const IListConst([]), this.selectedPeer});
  

@override@JsonKey() final  IMap<String, Peer> table;
@override@JsonKey() final  IList<String> view;
@override final  String? selectedPeer;

/// Create a copy of PeersState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PeersStateCopyWith<_PeersState> get copyWith => __$PeersStateCopyWithImpl<_PeersState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PeersState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedPeer, selectedPeer) || other.selectedPeer == selectedPeer));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedPeer);

@override
String toString() {
  return 'PeersState(table: $table, view: $view, selectedPeer: $selectedPeer)';
}


}

/// @nodoc
abstract mixin class _$PeersStateCopyWith<$Res> implements $PeersStateCopyWith<$Res> {
  factory _$PeersStateCopyWith(_PeersState value, $Res Function(_PeersState) _then) = __$PeersStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, Peer> table, IList<String> view, String? selectedPeer
});




}
/// @nodoc
class __$PeersStateCopyWithImpl<$Res>
    implements _$PeersStateCopyWith<$Res> {
  __$PeersStateCopyWithImpl(this._self, this._then);

  final _PeersState _self;
  final $Res Function(_PeersState) _then;

/// Create a copy of PeersState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? selectedPeer = freezed,}) {
  return _then(_PeersState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, Peer>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedPeer: freezed == selectedPeer ? _self.selectedPeer : selectedPeer // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
