// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'nodes_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NodesState {

 IMap<String, NodeInfo> get table; IList<String> get view; ISet<String> get expanded; String? get selectedNode; IMap<String, IList<String>> get results; String get tab; String? get action; String get historyRange; IMap<String, NodeDetail> get detail; IList<HistPoint> get history; String? get historyKey; String? get point; ISet<String> get checked; String? get anchor; String get treeFilter; String get pointFilter; ISet<String> get marked; IList<AuditEntry> get audit; ISet<String> get listed; String? get viewedPoint; String? get historyFailed; IMap<String, String> get listFailed; IMap<String, String> get metaFailed; HistWindow? get historyWindow; DateTime? get historyAt;
/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodesStateCopyWith<NodesState> get copyWith => _$NodesStateCopyWithImpl<NodesState>(this as NodesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NodesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodesState&&(identical(other.table, _this.table) || other.table == _this.table)&&const DeepCollectionEquality().equals(other.view, _this.view)&&const DeepCollectionEquality().equals(other.expanded, _this.expanded)&&(identical(other.selectedNode, _this.selectedNode) || other.selectedNode == _this.selectedNode)&&(identical(other.results, _this.results) || other.results == _this.results)&&(identical(other.tab, _this.tab) || other.tab == _this.tab)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.historyRange, _this.historyRange) || other.historyRange == _this.historyRange)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&const DeepCollectionEquality().equals(other.history, _this.history)&&(identical(other.historyKey, _this.historyKey) || other.historyKey == _this.historyKey)&&(identical(other.point, _this.point) || other.point == _this.point)&&const DeepCollectionEquality().equals(other.checked, _this.checked)&&(identical(other.anchor, _this.anchor) || other.anchor == _this.anchor)&&(identical(other.treeFilter, _this.treeFilter) || other.treeFilter == _this.treeFilter)&&(identical(other.pointFilter, _this.pointFilter) || other.pointFilter == _this.pointFilter)&&const DeepCollectionEquality().equals(other.marked, _this.marked)&&const DeepCollectionEquality().equals(other.audit, _this.audit)&&const DeepCollectionEquality().equals(other.listed, _this.listed)&&(identical(other.viewedPoint, _this.viewedPoint) || other.viewedPoint == _this.viewedPoint)&&(identical(other.historyFailed, _this.historyFailed) || other.historyFailed == _this.historyFailed)&&(identical(other.listFailed, _this.listFailed) || other.listFailed == _this.listFailed)&&(identical(other.metaFailed, _this.metaFailed) || other.metaFailed == _this.metaFailed)&&(identical(other.historyWindow, _this.historyWindow) || other.historyWindow == _this.historyWindow)&&(identical(other.historyAt, _this.historyAt) || other.historyAt == _this.historyAt));
}


@override
int get hashCode {
  final _this = this as NodesState;
  return Object.hashAll([runtimeType,_this.table,const DeepCollectionEquality().hash(_this.view),const DeepCollectionEquality().hash(_this.expanded),_this.selectedNode,_this.results,_this.tab,_this.action,_this.historyRange,_this.detail,const DeepCollectionEquality().hash(_this.history),_this.historyKey,_this.point,const DeepCollectionEquality().hash(_this.checked),_this.anchor,_this.treeFilter,_this.pointFilter,const DeepCollectionEquality().hash(_this.marked),const DeepCollectionEquality().hash(_this.audit),const DeepCollectionEquality().hash(_this.listed),_this.viewedPoint,_this.historyFailed,_this.listFailed,_this.metaFailed,_this.historyWindow,_this.historyAt]);
}

@override
String toString() {
  final _this = this as NodesState;
  return 'NodesState(table: ${_this.table}, view: ${_this.view}, expanded: ${_this.expanded}, selectedNode: ${_this.selectedNode}, results: ${_this.results}, tab: ${_this.tab}, action: ${_this.action}, historyRange: ${_this.historyRange}, detail: ${_this.detail}, history: ${_this.history}, historyKey: ${_this.historyKey}, point: ${_this.point}, checked: ${_this.checked}, anchor: ${_this.anchor}, treeFilter: ${_this.treeFilter}, pointFilter: ${_this.pointFilter}, marked: ${_this.marked}, audit: ${_this.audit}, listed: ${_this.listed}, viewedPoint: ${_this.viewedPoint}, historyFailed: ${_this.historyFailed}, listFailed: ${_this.listFailed}, metaFailed: ${_this.metaFailed}, historyWindow: ${_this.historyWindow}, historyAt: ${_this.historyAt})';
}


}

/// @nodoc
abstract mixin class $NodesStateCopyWith<$Res>  {
  factory $NodesStateCopyWith(NodesState value, $Res Function(NodesState) _then) = _$NodesStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, NodeInfo> table, IList<String> view, ISet<String> expanded, String? selectedNode, IMap<String, IList<String>> results, String tab, String? action, String historyRange, IMap<String, NodeDetail> detail, IList<HistPoint> history, String? historyKey, String? point, ISet<String> checked, String? anchor, String treeFilter, String pointFilter, ISet<String> marked, IList<AuditEntry> audit, ISet<String> listed, String? viewedPoint, String? historyFailed, IMap<String, String> listFailed, IMap<String, String> metaFailed, HistWindow? historyWindow, DateTime? historyAt
});


$HistWindowCopyWith<$Res>? get historyWindow;

}
/// @nodoc
class _$NodesStateCopyWithImpl<$Res>
    implements $NodesStateCopyWith<$Res> {
  _$NodesStateCopyWithImpl(this._self, this._then);

  final NodesState _self;
  final $Res Function(NodesState) _then;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? expanded = null,Object? selectedNode = freezed,Object? results = null,Object? tab = null,Object? action = freezed,Object? historyRange = null,Object? detail = null,Object? history = null,Object? historyKey = freezed,Object? point = freezed,Object? checked = null,Object? anchor = freezed,Object? treeFilter = null,Object? pointFilter = null,Object? marked = null,Object? audit = null,Object? listed = null,Object? viewedPoint = freezed,Object? historyFailed = freezed,Object? listFailed = null,Object? metaFailed = null,Object? historyWindow = freezed,Object? historyAt = freezed,}) {
  return _then(NodesState(
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
as String?,point: freezed == point ? _self.point : point // ignore: cast_nullable_to_non_nullable
as String?,checked: null == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as ISet<String>,anchor: freezed == anchor ? _self.anchor : anchor // ignore: cast_nullable_to_non_nullable
as String?,treeFilter: null == treeFilter ? _self.treeFilter : treeFilter // ignore: cast_nullable_to_non_nullable
as String,pointFilter: null == pointFilter ? _self.pointFilter : pointFilter // ignore: cast_nullable_to_non_nullable
as String,marked: null == marked ? _self.marked : marked // ignore: cast_nullable_to_non_nullable
as ISet<String>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,listed: null == listed ? _self.listed : listed // ignore: cast_nullable_to_non_nullable
as ISet<String>,viewedPoint: freezed == viewedPoint ? _self.viewedPoint : viewedPoint // ignore: cast_nullable_to_non_nullable
as String?,historyFailed: freezed == historyFailed ? _self.historyFailed : historyFailed // ignore: cast_nullable_to_non_nullable
as String?,listFailed: null == listFailed ? _self.listFailed : listFailed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,metaFailed: null == metaFailed ? _self.metaFailed : metaFailed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,historyWindow: freezed == historyWindow ? _self.historyWindow : historyWindow // ignore: cast_nullable_to_non_nullable
as HistWindow?,historyAt: freezed == historyAt ? _self.historyAt : historyAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get historyWindow {
    if (_self.historyWindow == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.historyWindow!, (value) {
    return _then(_self.copyWith(historyWindow: value));
  });
}
}



/// @nodoc


class _NodesState implements NodesState {
  const _NodesState({this.table = const IMapConst({}), this.view = const IListConst([]), this.expanded = const ISetConst({}), this.selectedNode, this.results = const IMapConst({}), this.tab = 'points', this.action, this.historyRange = '1h', this.detail = const IMapConst({}), this.history = const IListConst([]), this.historyKey, this.point, this.checked = const ISetConst({}), this.anchor, this.treeFilter = '', this.pointFilter = '', this.marked = const ISetConst({}), this.audit = const IListConst([]), this.listed = const ISetConst({}), this.viewedPoint, this.historyFailed, this.listFailed = const IMapConst({}), this.metaFailed = const IMapConst({}), this.historyWindow, this.historyAt});
  

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
@override final  String? point;
@override@JsonKey() final  ISet<String> checked;
@override final  String? anchor;
@override@JsonKey() final  String treeFilter;
@override@JsonKey() final  String pointFilter;
@override@JsonKey() final  ISet<String> marked;
@override@JsonKey() final  IList<AuditEntry> audit;
@override@JsonKey() final  ISet<String> listed;
@override final  String? viewedPoint;
@override final  String? historyFailed;
@override@JsonKey() final  IMap<String, String> listFailed;
@override@JsonKey() final  IMap<String, String> metaFailed;
@override final  HistWindow? historyWindow;
@override final  DateTime? historyAt;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodesStateCopyWith<_NodesState> get copyWith => __$NodesStateCopyWithImpl<_NodesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodesState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&const DeepCollectionEquality().equals(other.expanded, expanded)&&(identical(other.selectedNode, selectedNode) || other.selectedNode == selectedNode)&&(identical(other.results, results) || other.results == results)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.action, action) || other.action == action)&&(identical(other.historyRange, historyRange) || other.historyRange == historyRange)&&(identical(other.detail, detail) || other.detail == detail)&&const DeepCollectionEquality().equals(other.history, history)&&(identical(other.historyKey, historyKey) || other.historyKey == historyKey)&&(identical(other.point, point) || other.point == point)&&const DeepCollectionEquality().equals(other.checked, checked)&&(identical(other.anchor, anchor) || other.anchor == anchor)&&(identical(other.treeFilter, treeFilter) || other.treeFilter == treeFilter)&&(identical(other.pointFilter, pointFilter) || other.pointFilter == pointFilter)&&const DeepCollectionEquality().equals(other.marked, marked)&&const DeepCollectionEquality().equals(other.audit, audit)&&const DeepCollectionEquality().equals(other.listed, listed)&&(identical(other.viewedPoint, viewedPoint) || other.viewedPoint == viewedPoint)&&(identical(other.historyFailed, historyFailed) || other.historyFailed == historyFailed)&&(identical(other.listFailed, listFailed) || other.listFailed == listFailed)&&(identical(other.metaFailed, metaFailed) || other.metaFailed == metaFailed)&&(identical(other.historyWindow, historyWindow) || other.historyWindow == historyWindow)&&(identical(other.historyAt, historyAt) || other.historyAt == historyAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,table,const DeepCollectionEquality().hash(view),const DeepCollectionEquality().hash(expanded),selectedNode,results,tab,action,historyRange,detail,const DeepCollectionEquality().hash(history),historyKey,point,const DeepCollectionEquality().hash(checked),anchor,treeFilter,pointFilter,const DeepCollectionEquality().hash(marked),const DeepCollectionEquality().hash(audit),const DeepCollectionEquality().hash(listed),viewedPoint,historyFailed,listFailed,metaFailed,historyWindow,historyAt]);
}

@override
String toString() {
    return 'NodesState(table: $table, view: $view, expanded: $expanded, selectedNode: $selectedNode, results: $results, tab: $tab, action: $action, historyRange: $historyRange, detail: $detail, history: $history, historyKey: $historyKey, point: $point, checked: $checked, anchor: $anchor, treeFilter: $treeFilter, pointFilter: $pointFilter, marked: $marked, audit: $audit, listed: $listed, viewedPoint: $viewedPoint, historyFailed: $historyFailed, listFailed: $listFailed, metaFailed: $metaFailed, historyWindow: $historyWindow, historyAt: $historyAt)';
}


}

/// @nodoc
abstract mixin class _$NodesStateCopyWith<$Res> implements $NodesStateCopyWith<$Res> {
  factory _$NodesStateCopyWith(_NodesState value, $Res Function(_NodesState) _then) = __$NodesStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, NodeInfo> table, IList<String> view, ISet<String> expanded, String? selectedNode, IMap<String, IList<String>> results, String tab, String? action, String historyRange, IMap<String, NodeDetail> detail, IList<HistPoint> history, String? historyKey, String? point, ISet<String> checked, String? anchor, String treeFilter, String pointFilter, ISet<String> marked, IList<AuditEntry> audit, ISet<String> listed, String? viewedPoint, String? historyFailed, IMap<String, String> listFailed, IMap<String, String> metaFailed, HistWindow? historyWindow, DateTime? historyAt
});


@override $HistWindowCopyWith<$Res>? get historyWindow;

}
/// @nodoc
class __$NodesStateCopyWithImpl<$Res>
    implements _$NodesStateCopyWith<$Res> {
  __$NodesStateCopyWithImpl(this._self, this._then);

  final _NodesState _self;
  final $Res Function(_NodesState) _then;

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? expanded = null,Object? selectedNode = freezed,Object? results = null,Object? tab = null,Object? action = freezed,Object? historyRange = null,Object? detail = null,Object? history = null,Object? historyKey = freezed,Object? point = freezed,Object? checked = null,Object? anchor = freezed,Object? treeFilter = null,Object? pointFilter = null,Object? marked = null,Object? audit = null,Object? listed = null,Object? viewedPoint = freezed,Object? historyFailed = freezed,Object? listFailed = null,Object? metaFailed = null,Object? historyWindow = freezed,Object? historyAt = freezed,}) {
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
as String?,point: freezed == point ? _self.point : point // ignore: cast_nullable_to_non_nullable
as String?,checked: null == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as ISet<String>,anchor: freezed == anchor ? _self.anchor : anchor // ignore: cast_nullable_to_non_nullable
as String?,treeFilter: null == treeFilter ? _self.treeFilter : treeFilter // ignore: cast_nullable_to_non_nullable
as String,pointFilter: null == pointFilter ? _self.pointFilter : pointFilter // ignore: cast_nullable_to_non_nullable
as String,marked: null == marked ? _self.marked : marked // ignore: cast_nullable_to_non_nullable
as ISet<String>,audit: null == audit ? _self.audit : audit // ignore: cast_nullable_to_non_nullable
as IList<AuditEntry>,listed: null == listed ? _self.listed : listed // ignore: cast_nullable_to_non_nullable
as ISet<String>,viewedPoint: freezed == viewedPoint ? _self.viewedPoint : viewedPoint // ignore: cast_nullable_to_non_nullable
as String?,historyFailed: freezed == historyFailed ? _self.historyFailed : historyFailed // ignore: cast_nullable_to_non_nullable
as String?,listFailed: null == listFailed ? _self.listFailed : listFailed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,metaFailed: null == metaFailed ? _self.metaFailed : metaFailed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,historyWindow: freezed == historyWindow ? _self.historyWindow : historyWindow // ignore: cast_nullable_to_non_nullable
as HistWindow?,historyAt: freezed == historyAt ? _self.historyAt : historyAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of NodesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get historyWindow {
    if (_self.historyWindow == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.historyWindow!, (value) {
    return _then(_self.copyWith(historyWindow: value));
  });
}
}

// dart format on
