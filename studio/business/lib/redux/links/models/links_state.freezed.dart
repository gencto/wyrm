// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'links_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinksState {

 IMap<String, LinkInfo> get table; IList<String> get view; LinksTab get tab; String? get selectedLink; IList<String> get log; IList<LinkRevision> get revisions; String? get version;
/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinksStateCopyWith<LinksState> get copyWith => _$LinksStateCopyWithImpl<LinksState>(this as LinksState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LinksState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinksState&&(identical(other.table, _this.table) || other.table == _this.table)&&const DeepCollectionEquality().equals(other.view, _this.view)&&(identical(other.tab, _this.tab) || other.tab == _this.tab)&&(identical(other.selectedLink, _this.selectedLink) || other.selectedLink == _this.selectedLink)&&const DeepCollectionEquality().equals(other.log, _this.log)&&const DeepCollectionEquality().equals(other.revisions, _this.revisions)&&(identical(other.version, _this.version) || other.version == _this.version));
}


@override
int get hashCode {
  final _this = this as LinksState;
  return Object.hash(runtimeType,_this.table,const DeepCollectionEquality().hash(_this.view),_this.tab,_this.selectedLink,const DeepCollectionEquality().hash(_this.log),const DeepCollectionEquality().hash(_this.revisions),_this.version);
}

@override
String toString() {
  final _this = this as LinksState;
  return 'LinksState(table: ${_this.table}, view: ${_this.view}, tab: ${_this.tab}, selectedLink: ${_this.selectedLink}, log: ${_this.log}, revisions: ${_this.revisions}, version: ${_this.version})';
}


}

/// @nodoc
abstract mixin class $LinksStateCopyWith<$Res>  {
  factory $LinksStateCopyWith(LinksState value, $Res Function(LinksState) _then) = _$LinksStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, LinkInfo> table, IList<String> view, LinksTab tab, String? selectedLink, IList<String> log, IList<LinkRevision> revisions, String? version
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
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? tab = null,Object? selectedLink = freezed,Object? log = null,Object? revisions = null,Object? version = freezed,}) {
  return _then(LinksState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, LinkInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as LinksTab,selectedLink: freezed == selectedLink ? _self.selectedLink : selectedLink // ignore: cast_nullable_to_non_nullable
as String?,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,revisions: null == revisions ? _self.revisions : revisions // ignore: cast_nullable_to_non_nullable
as IList<LinkRevision>,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _LinksState implements LinksState {
  const _LinksState({this.table = const IMapConst({}), this.view = const IListConst([]), this.tab = LinksTab.local, this.selectedLink, this.log = const IListConst([]), this.revisions = const IListConst([]), this.version});
  

@override@JsonKey() final  IMap<String, LinkInfo> table;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  LinksTab tab;
@override final  String? selectedLink;
@override@JsonKey() final  IList<String> log;
@override@JsonKey() final  IList<LinkRevision> revisions;
@override final  String? version;

/// Create a copy of LinksState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinksStateCopyWith<_LinksState> get copyWith => __$LinksStateCopyWithImpl<_LinksState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinksState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.selectedLink, selectedLink) || other.selectedLink == selectedLink)&&const DeepCollectionEquality().equals(other.log, log)&&const DeepCollectionEquality().equals(other.revisions, revisions)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),tab,selectedLink,const DeepCollectionEquality().hash(log),const DeepCollectionEquality().hash(revisions),version);
}

@override
String toString() {
    return 'LinksState(table: $table, view: $view, tab: $tab, selectedLink: $selectedLink, log: $log, revisions: $revisions, version: $version)';
}


}

/// @nodoc
abstract mixin class _$LinksStateCopyWith<$Res> implements $LinksStateCopyWith<$Res> {
  factory _$LinksStateCopyWith(_LinksState value, $Res Function(_LinksState) _then) = __$LinksStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, LinkInfo> table, IList<String> view, LinksTab tab, String? selectedLink, IList<String> log, IList<LinkRevision> revisions, String? version
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
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? tab = null,Object? selectedLink = freezed,Object? log = null,Object? revisions = null,Object? version = freezed,}) {
  return _then(_LinksState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, LinkInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as LinksTab,selectedLink: freezed == selectedLink ? _self.selectedLink : selectedLink // ignore: cast_nullable_to_non_nullable
as String?,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,revisions: null == revisions ? _self.revisions : revisions // ignore: cast_nullable_to_non_nullable
as IList<LinkRevision>,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
