// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowEditorState {

 String? get flowId; Object? get draft; bool get dirty; IList<String> get problems; String? get selectedBlock;
/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowEditorStateCopyWith<FlowEditorState> get copyWith => _$FlowEditorStateCopyWithImpl<FlowEditorState>(this as FlowEditorState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowEditorState&&(identical(other.flowId, flowId) || other.flowId == flowId)&&const DeepCollectionEquality().equals(other.draft, draft)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.problems, problems)&&(identical(other.selectedBlock, selectedBlock) || other.selectedBlock == selectedBlock));
}


@override
int get hashCode => Object.hash(runtimeType,flowId,const DeepCollectionEquality().hash(draft),dirty,const DeepCollectionEquality().hash(problems),selectedBlock);

@override
String toString() {
  return 'FlowEditorState(flowId: $flowId, draft: $draft, dirty: $dirty, problems: $problems, selectedBlock: $selectedBlock)';
}


}

/// @nodoc
abstract mixin class $FlowEditorStateCopyWith<$Res>  {
  factory $FlowEditorStateCopyWith(FlowEditorState value, $Res Function(FlowEditorState) _then) = _$FlowEditorStateCopyWithImpl;
@useResult
$Res call({
 String? flowId, Object? draft, bool dirty, IList<String> problems, String? selectedBlock
});




}
/// @nodoc
class _$FlowEditorStateCopyWithImpl<$Res>
    implements $FlowEditorStateCopyWith<$Res> {
  _$FlowEditorStateCopyWithImpl(this._self, this._then);

  final FlowEditorState _self;
  final $Res Function(FlowEditorState) _then;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? flowId = freezed,Object? draft = freezed,Object? dirty = null,Object? problems = null,Object? selectedBlock = freezed,}) {
  return _then(_self.copyWith(
flowId: freezed == flowId ? _self.flowId : flowId // ignore: cast_nullable_to_non_nullable
as String?,draft: freezed == draft ? _self.draft : draft ,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedBlock: freezed == selectedBlock ? _self.selectedBlock : selectedBlock // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _FlowEditorState implements FlowEditorState {
  const _FlowEditorState({this.flowId, this.draft, this.dirty = false, this.problems = const IListConst([]), this.selectedBlock});
  

@override final  String? flowId;
@override final  Object? draft;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  IList<String> problems;
@override final  String? selectedBlock;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowEditorStateCopyWith<_FlowEditorState> get copyWith => __$FlowEditorStateCopyWithImpl<_FlowEditorState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowEditorState&&(identical(other.flowId, flowId) || other.flowId == flowId)&&const DeepCollectionEquality().equals(other.draft, draft)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.problems, problems)&&(identical(other.selectedBlock, selectedBlock) || other.selectedBlock == selectedBlock));
}


@override
int get hashCode => Object.hash(runtimeType,flowId,const DeepCollectionEquality().hash(draft),dirty,const DeepCollectionEquality().hash(problems),selectedBlock);

@override
String toString() {
  return 'FlowEditorState(flowId: $flowId, draft: $draft, dirty: $dirty, problems: $problems, selectedBlock: $selectedBlock)';
}


}

/// @nodoc
abstract mixin class _$FlowEditorStateCopyWith<$Res> implements $FlowEditorStateCopyWith<$Res> {
  factory _$FlowEditorStateCopyWith(_FlowEditorState value, $Res Function(_FlowEditorState) _then) = __$FlowEditorStateCopyWithImpl;
@override @useResult
$Res call({
 String? flowId, Object? draft, bool dirty, IList<String> problems, String? selectedBlock
});




}
/// @nodoc
class __$FlowEditorStateCopyWithImpl<$Res>
    implements _$FlowEditorStateCopyWith<$Res> {
  __$FlowEditorStateCopyWithImpl(this._self, this._then);

  final _FlowEditorState _self;
  final $Res Function(_FlowEditorState) _then;

/// Create a copy of FlowEditorState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? flowId = freezed,Object? draft = freezed,Object? dirty = null,Object? problems = null,Object? selectedBlock = freezed,}) {
  return _then(_FlowEditorState(
flowId: freezed == flowId ? _self.flowId : flowId // ignore: cast_nullable_to_non_nullable
as String?,draft: freezed == draft ? _self.draft : draft ,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedBlock: freezed == selectedBlock ? _self.selectedBlock : selectedBlock // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
