// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'nodes_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NodesState {

 IMap<String, NodeInfo> get table; IList<String> get view; ISet<String> get expanded; String? get selectedNode; IMap<String, IList<String>> get results; String get tab; String? get action; String get historyRange; IMap<String, NodeDetail> get detail; IList<HistPoint> get history; String? get historyKey;
/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodesStateCopyWith<NodesState> get copyWith => _$NodesStateCopyWithImpl<NodesState>(this as NodesState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&const DeepCollectionEquality().equals(other.expanded, expanded)&&(identical(other.selectedNode, selectedNode) || other.selectedNode == selectedNode)&&(identical(other.results, results) || other.results == results)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.action, action) || other.action == action)&&(identical(other.historyRange, historyRange) || other.historyRange == historyRange)&&(identical(other.detail, detail) || other.detail == detail)&&const DeepCollectionEquality().equals(other.history, history)&&(identical(other.historyKey, historyKey) || other.historyKey == historyKey));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),const DeepCollectionEquality().hash(expanded),selectedNode,results,tab,action,historyRange,detail,const DeepCollectionEquality().hash(history),historyKey);

@override
String toString() {
  return 'NodesState(table: $table, view: $view, expanded: $expanded, selectedNode: $selectedNode, results: $results, tab: $tab, action: $action, historyRange: $historyRange, detail: $detail, history: $history, historyKey: $historyKey)';
}


}

/// @nodoc
abstract mixin class $NodesStateCopyWith<$Res>  {
  factory $NodesStateCopyWith(NodesState value, $Res Function(NodesState) _then) = _$NodesStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, NodeInfo> table, IList<String> view, ISet<String> expanded, String? selectedNode, IMap<String, IList<String>> results, String tab, String? action, String historyRange, IMap<String, NodeDetail> detail, IList<HistPoint> history, String? historyKey
});




}
/// @nodoc
class _$NodesStateCopyWithImpl<$Res>
    implements $NodesStateCopyWith<$Res> {
  _$NodesStateCopyWithImpl(this._self, this._then);

  final NodesState _self;
  final $Res Function(NodesState) _then;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? expanded = null,Object? selectedNode = freezed,Object? results = null,Object? tab = null,Object? action = freezed,Object? historyRange = null,Object? detail = null,Object? history = null,Object? historyKey = freezed,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, NodeInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,expanded: null == expanded ? _self.expanded : expanded // ignore: cast_nullable_to_non_nullable
as ISet<String>,selectedNode: freezed == selectedNode ? _self.selectedNode : selectedNode // ignore: cast_nullable_to_non_nullable
as String?,results: null == results ? _self.results : results // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<String>>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,historyRange: null == historyRange ? _self.historyRange : historyRange // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as IMap<String, NodeDetail>,history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as IList<HistPoint>,historyKey: freezed == historyKey ? _self.historyKey : historyKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _NodesState implements NodesState {
  const _NodesState({this.table = const IMapConst({}), this.view = const IListConst([]), this.expanded = const ISetConst({}), this.selectedNode, this.results = const IMapConst({}), this.tab = 'points', this.action, this.historyRange = '1h', this.detail = const IMapConst({}), this.history = const IListConst([]), this.historyKey});
  

@override@JsonKey() final  IMap<String, NodeInfo> table;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  ISet<String> expanded;
@override final  String? selectedNode;
@override@JsonKey() final  IMap<String, IList<String>> results;
@override@JsonKey() final  String tab;
@override final  String? action;
@override@JsonKey() final  String historyRange;
@override@JsonKey() final  IMap<String, NodeDetail> detail;
@override@JsonKey() final  IList<HistPoint> history;
@override final  String? historyKey;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodesStateCopyWith<_NodesState> get copyWith => __$NodesStateCopyWithImpl<_NodesState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&const DeepCollectionEquality().equals(other.expanded, expanded)&&(identical(other.selectedNode, selectedNode) || other.selectedNode == selectedNode)&&(identical(other.results, results) || other.results == results)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.action, action) || other.action == action)&&(identical(other.historyRange, historyRange) || other.historyRange == historyRange)&&(identical(other.detail, detail) || other.detail == detail)&&const DeepCollectionEquality().equals(other.history, history)&&(identical(other.historyKey, historyKey) || other.historyKey == historyKey));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),const DeepCollectionEquality().hash(expanded),selectedNode,results,tab,action,historyRange,detail,const DeepCollectionEquality().hash(history),historyKey);

@override
String toString() {
  return 'NodesState(table: $table, view: $view, expanded: $expanded, selectedNode: $selectedNode, results: $results, tab: $tab, action: $action, historyRange: $historyRange, detail: $detail, history: $history, historyKey: $historyKey)';
}


}

/// @nodoc
abstract mixin class _$NodesStateCopyWith<$Res> implements $NodesStateCopyWith<$Res> {
  factory _$NodesStateCopyWith(_NodesState value, $Res Function(_NodesState) _then) = __$NodesStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, NodeInfo> table, IList<String> view, ISet<String> expanded, String? selectedNode, IMap<String, IList<String>> results, String tab, String? action, String historyRange, IMap<String, NodeDetail> detail, IList<HistPoint> history, String? historyKey
});




}
/// @nodoc
class __$NodesStateCopyWithImpl<$Res>
    implements _$NodesStateCopyWith<$Res> {
  __$NodesStateCopyWithImpl(this._self, this._then);

  final _NodesState _self;
  final $Res Function(_NodesState) _then;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? expanded = null,Object? selectedNode = freezed,Object? results = null,Object? tab = null,Object? action = freezed,Object? historyRange = null,Object? detail = null,Object? history = null,Object? historyKey = freezed,}) {
  return _then(_NodesState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, NodeInfo>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,expanded: null == expanded ? _self.expanded : expanded // ignore: cast_nullable_to_non_nullable
as ISet<String>,selectedNode: freezed == selectedNode ? _self.selectedNode : selectedNode // ignore: cast_nullable_to_non_nullable
as String?,results: null == results ? _self.results : results // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<String>>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,historyRange: null == historyRange ? _self.historyRange : historyRange // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as IMap<String, NodeDetail>,history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as IList<HistPoint>,historyKey: freezed == historyKey ? _self.historyKey : historyKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
