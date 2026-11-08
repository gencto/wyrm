// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'links_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinksState {

 IMap<String, LinkInfo> get table; IList<String> get view; LinksTab get tab; String? get selectedLink;
/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinksStateCopyWith<LinksState> get copyWith => _$LinksStateCopyWithImpl<LinksState>(this as LinksState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinksState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.selectedLink, selectedLink) || other.selectedLink == selectedLink));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),tab,selectedLink);

@override
String toString() {
  return 'LinksState(table: $table, view: $view, tab: $tab, selectedLink: $selectedLink)';
}


}

/// @nodoc
abstract mixin class $LinksStateCopyWith<$Res>  {
  factory $LinksStateCopyWith(LinksState value, $Res Function(LinksState) _then) = _$LinksStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, LinkInfo> table, IList<String> view, LinksTab tab, String? selectedLink
});




}
/// @nodoc
class _$LinksStateCopyWithImpl<$Res>
    implements $LinksStateCopyWith<$Res> {
  _$LinksStateCopyWithImpl(this._self, this._then);

  final LinksState _self;
  final $Res Function(LinksState) _then;

/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? tab = null,Object? selectedLink = freezed,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, LinkInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as LinksTab,selectedLink: freezed == selectedLink ? _self.selectedLink : selectedLink // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _LinksState implements LinksState {
  const _LinksState({this.table = const IMapConst({}), this.view = const IListConst([]), this.tab = LinksTab.local, this.selectedLink});
  

@override@JsonKey() final  IMap<String, LinkInfo> table;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  LinksTab tab;
@override final  String? selectedLink;

/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinksStateCopyWith<_LinksState> get copyWith => __$LinksStateCopyWithImpl<_LinksState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinksState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.selectedLink, selectedLink) || other.selectedLink == selectedLink));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),tab,selectedLink);

@override
String toString() {
  return 'LinksState(table: $table, view: $view, tab: $tab, selectedLink: $selectedLink)';
}


}

/// @nodoc
abstract mixin class _$LinksStateCopyWith<$Res> implements $LinksStateCopyWith<$Res> {
  factory _$LinksStateCopyWith(_LinksState value, $Res Function(_LinksState) _then) = __$LinksStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, LinkInfo> table, IList<String> view, LinksTab tab, String? selectedLink
});




}
/// @nodoc
class __$LinksStateCopyWithImpl<$Res>
    implements _$LinksStateCopyWith<$Res> {
  __$LinksStateCopyWithImpl(this._self, this._then);

  final _LinksState _self;
  final $Res Function(_LinksState) _then;

/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? tab = null,Object? selectedLink = freezed,}) {
  return _then(_LinksState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, LinkInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as LinksTab,selectedLink: freezed == selectedLink ? _self.selectedLink : selectedLink // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
