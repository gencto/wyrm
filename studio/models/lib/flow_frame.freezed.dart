// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_frame.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowFrame {

/// The draft the canvas showed: the flow, or the block one level up.
 FlowDraft get draft;/// The custom block whose inside is shown now.
 String get block;/// The instance it was opened from: its inner nodes' live values are
/// the rows `<instance>/<inner>`. Null: opened from the palette.
 String? get instance; IList<FlowDraft> get undo; IList<FlowDraft> get redo; ISet<String> get selection;
/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowFrameCopyWith<FlowFrame> get copyWith => _$FlowFrameCopyWithImpl<FlowFrame>(this as FlowFrame, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowFrame&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.block, block) || other.block == block)&&(identical(other.instance, instance) || other.instance == instance)&&const DeepCollectionEquality().equals(other.undo, undo)&&const DeepCollectionEquality().equals(other.redo, redo)&&const DeepCollectionEquality().equals(other.selection, selection));
}


@override
int get hashCode => Object.hash(runtimeType,draft,block,instance,const DeepCollectionEquality().hash(undo),const DeepCollectionEquality().hash(redo),const DeepCollectionEquality().hash(selection));

@override
String toString() {
  return 'FlowFrame(draft: $draft, block: $block, instance: $instance, undo: $undo, redo: $redo, selection: $selection)';
}


}

/// @nodoc
abstract mixin class $FlowFrameCopyWith<$Res>  {
  factory $FlowFrameCopyWith(FlowFrame value, $Res Function(FlowFrame) _then) = _$FlowFrameCopyWithImpl;
@useResult
$Res call({
 FlowDraft draft, String block, String? instance, IList<FlowDraft> undo, IList<FlowDraft> redo, ISet<String> selection
});


$FlowDraftCopyWith<$Res> get draft;

}
/// @nodoc
class _$FlowFrameCopyWithImpl<$Res>
    implements $FlowFrameCopyWith<$Res> {
  _$FlowFrameCopyWithImpl(this._self, this._then);

  final FlowFrame _self;
  final $Res Function(FlowFrame) _then;

/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draft = null,Object? block = null,Object? instance = freezed,Object? undo = null,Object? redo = null,Object? selection = null,}) {
  return _then(_self.copyWith(
draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as FlowDraft,block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String,instance: freezed == instance ? _self.instance : instance // ignore: cast_nullable_to_non_nullable
as String?,undo: null == undo ? _self.undo : undo // ignore: cast_nullable_to_non_nullable
as IList<FlowDraft>,redo: null == redo ? _self.redo : redo // ignore: cast_nullable_to_non_nullable
as IList<FlowDraft>,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ISet<String>,
  ));
}
/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res> get draft {
  
  return $FlowDraftCopyWith<$Res>(_self.draft, (value) {
    return _then(_self.copyWith(draft: value));
  });
}
}



/// @nodoc


class _FlowFrame implements FlowFrame {
  const _FlowFrame({required this.draft, required this.block, this.instance, this.undo = const IListConst([]), this.redo = const IListConst([]), this.selection = const ISetConst({})});
  

/// The draft the canvas showed: the flow, or the block one level up.
@override final  FlowDraft draft;
/// The custom block whose inside is shown now.
@override final  String block;
/// The instance it was opened from: its inner nodes' live values are
/// the rows `<instance>/<inner>`. Null: opened from the palette.
@override final  String? instance;
@override@JsonKey() final  IList<FlowDraft> undo;
@override@JsonKey() final  IList<FlowDraft> redo;
@override@JsonKey() final  ISet<String> selection;

/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowFrameCopyWith<_FlowFrame> get copyWith => __$FlowFrameCopyWithImpl<_FlowFrame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowFrame&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.block, block) || other.block == block)&&(identical(other.instance, instance) || other.instance == instance)&&const DeepCollectionEquality().equals(other.undo, undo)&&const DeepCollectionEquality().equals(other.redo, redo)&&const DeepCollectionEquality().equals(other.selection, selection));
}


@override
int get hashCode => Object.hash(runtimeType,draft,block,instance,const DeepCollectionEquality().hash(undo),const DeepCollectionEquality().hash(redo),const DeepCollectionEquality().hash(selection));

@override
String toString() {
  return 'FlowFrame(draft: $draft, block: $block, instance: $instance, undo: $undo, redo: $redo, selection: $selection)';
}


}

/// @nodoc
abstract mixin class _$FlowFrameCopyWith<$Res> implements $FlowFrameCopyWith<$Res> {
  factory _$FlowFrameCopyWith(_FlowFrame value, $Res Function(_FlowFrame) _then) = __$FlowFrameCopyWithImpl;
@override @useResult
$Res call({
 FlowDraft draft, String block, String? instance, IList<FlowDraft> undo, IList<FlowDraft> redo, ISet<String> selection
});


@override $FlowDraftCopyWith<$Res> get draft;

}
/// @nodoc
class __$FlowFrameCopyWithImpl<$Res>
    implements _$FlowFrameCopyWith<$Res> {
  __$FlowFrameCopyWithImpl(this._self, this._then);

  final _FlowFrame _self;
  final $Res Function(_FlowFrame) _then;

/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draft = null,Object? block = null,Object? instance = freezed,Object? undo = null,Object? redo = null,Object? selection = null,}) {
  return _then(_FlowFrame(
draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as FlowDraft,block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String,instance: freezed == instance ? _self.instance : instance // ignore: cast_nullable_to_non_nullable
as String?,undo: null == undo ? _self.undo : undo // ignore: cast_nullable_to_non_nullable
as IList<FlowDraft>,redo: null == redo ? _self.redo : redo // ignore: cast_nullable_to_non_nullable
as IList<FlowDraft>,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ISet<String>,
  ));
}

/// Create a copy of FlowFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res> get draft {
  
  return $FlowDraftCopyWith<$Res>(_self.draft, (value) {
    return _then(_self.copyWith(draft: value));
  });
}
}

// dart format on
