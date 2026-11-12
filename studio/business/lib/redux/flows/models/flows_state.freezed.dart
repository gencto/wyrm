// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flows_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowsState {

 String? get query; IList<String> get view; IMap<String, FlowSummary> get table; String? get selectedFlow; IMap<String, Object> get defs; IList<NodeType> get blockTypes; LiveSet? get follow;
/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowsStateCopyWith<FlowsState> get copyWith => _$FlowsStateCopyWithImpl<FlowsState>(this as FlowsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowsState&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.table, table) || other.table == table)&&(identical(other.selectedFlow, selectedFlow) || other.selectedFlow == selectedFlow)&&(identical(other.defs, defs) || other.defs == defs)&&const DeepCollectionEquality().equals(other.blockTypes, blockTypes)&&(identical(other.follow, follow) || other.follow == follow));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(view),table,selectedFlow,defs,const DeepCollectionEquality().hash(blockTypes),follow);

@override
String toString() {
  return 'FlowsState(query: $query, view: $view, table: $table, selectedFlow: $selectedFlow, defs: $defs, blockTypes: $blockTypes, follow: $follow)';
}


}

/// @nodoc
abstract mixin class $FlowsStateCopyWith<$Res>  {
  factory $FlowsStateCopyWith(FlowsState value, $Res Function(FlowsState) _then) = _$FlowsStateCopyWithImpl;
@useResult
$Res call({
 String? query, IList<String> view, IMap<String, FlowSummary> table, String? selectedFlow, IMap<String, Object> defs, IList<NodeType> blockTypes, LiveSet? follow
});


$LiveSetCopyWith<$Res>? get follow;

}
/// @nodoc
class _$FlowsStateCopyWithImpl<$Res>
    implements $FlowsStateCopyWith<$Res> {
  _$FlowsStateCopyWithImpl(this._self, this._then);

  final FlowsState _self;
  final $Res Function(FlowsState) _then;

/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = freezed,Object? view = null,Object? table = null,Object? selectedFlow = freezed,Object? defs = null,Object? blockTypes = null,Object? follow = freezed,}) {
  return _then(_self.copyWith(
query: freezed == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String?,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowSummary>,selectedFlow: freezed == selectedFlow ? _self.selectedFlow : selectedFlow // ignore: cast_nullable_to_non_nullable
as String?,defs: null == defs ? _self.defs : defs // ignore: cast_nullable_to_non_nullable
as IMap<String, Object>,blockTypes: null == blockTypes ? _self.blockTypes : blockTypes // ignore: cast_nullable_to_non_nullable
as IList<NodeType>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,
  ));
}
/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveSetCopyWith<$Res>? get follow {
    if (_self.follow == null) {
    return null;
  }

  return $LiveSetCopyWith<$Res>(_self.follow!, (value) {
    return _then(_self.copyWith(follow: value));
  });
}
}



/// @nodoc


class _FlowsState implements FlowsState {
  const _FlowsState({this.query, this.view = const IListConst([]), this.table = const IMapConst({}), this.selectedFlow, this.defs = const IMapConst({}), this.blockTypes = const IListConst([]), this.follow});
  

@override final  String? query;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  IMap<String, FlowSummary> table;
@override final  String? selectedFlow;
@override@JsonKey() final  IMap<String, Object> defs;
@override@JsonKey() final  IList<NodeType> blockTypes;
@override final  LiveSet? follow;

/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowsStateCopyWith<_FlowsState> get copyWith => __$FlowsStateCopyWithImpl<_FlowsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowsState&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.table, table) || other.table == table)&&(identical(other.selectedFlow, selectedFlow) || other.selectedFlow == selectedFlow)&&(identical(other.defs, defs) || other.defs == defs)&&const DeepCollectionEquality().equals(other.blockTypes, blockTypes)&&(identical(other.follow, follow) || other.follow == follow));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(view),table,selectedFlow,defs,const DeepCollectionEquality().hash(blockTypes),follow);

@override
String toString() {
  return 'FlowsState(query: $query, view: $view, table: $table, selectedFlow: $selectedFlow, defs: $defs, blockTypes: $blockTypes, follow: $follow)';
}


}

/// @nodoc
abstract mixin class _$FlowsStateCopyWith<$Res> implements $FlowsStateCopyWith<$Res> {
  factory _$FlowsStateCopyWith(_FlowsState value, $Res Function(_FlowsState) _then) = __$FlowsStateCopyWithImpl;
@override @useResult
$Res call({
 String? query, IList<String> view, IMap<String, FlowSummary> table, String? selectedFlow, IMap<String, Object> defs, IList<NodeType> blockTypes, LiveSet? follow
});


@override $LiveSetCopyWith<$Res>? get follow;

}
/// @nodoc
class __$FlowsStateCopyWithImpl<$Res>
    implements _$FlowsStateCopyWith<$Res> {
  __$FlowsStateCopyWithImpl(this._self, this._then);

  final _FlowsState _self;
  final $Res Function(_FlowsState) _then;

/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? query = freezed,Object? view = null,Object? table = null,Object? selectedFlow = freezed,Object? defs = null,Object? blockTypes = null,Object? follow = freezed,}) {
  return _then(_FlowsState(
query: freezed == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String?,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, FlowSummary>,selectedFlow: freezed == selectedFlow ? _self.selectedFlow : selectedFlow // ignore: cast_nullable_to_non_nullable
as String?,defs: null == defs ? _self.defs : defs // ignore: cast_nullable_to_non_nullable
as IMap<String, Object>,blockTypes: null == blockTypes ? _self.blockTypes : blockTypes // ignore: cast_nullable_to_non_nullable
as IList<NodeType>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,
  ));
}

/// Create a copy of FlowsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveSetCopyWith<$Res>? get follow {
    if (_self.follow == null) {
    return null;
  }

  return $LiveSetCopyWith<$Res>(_self.follow!, (value) {
    return _then(_self.copyWith(follow: value));
  });
}
}

// dart format on
