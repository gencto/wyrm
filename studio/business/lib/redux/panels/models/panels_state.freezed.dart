// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'panels_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PanelsState {

 IMap<PanelSlot, double> get widths;
/// Create a copy of PanelsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PanelsStateCopyWith<PanelsState> get copyWith => _$PanelsStateCopyWithImpl<PanelsState>(this as PanelsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PanelsState&&(identical(other.widths, widths) || other.widths == widths));
}


@override
int get hashCode => Object.hash(runtimeType,widths);

@override
String toString() {
  return 'PanelsState(widths: $widths)';
}


}

/// @nodoc
abstract mixin class $PanelsStateCopyWith<$Res>  {
  factory $PanelsStateCopyWith(PanelsState value, $Res Function(PanelsState) _then) = _$PanelsStateCopyWithImpl;
@useResult
$Res call({
 IMap<PanelSlot, double> widths
});




}
/// @nodoc
class _$PanelsStateCopyWithImpl<$Res>
    implements $PanelsStateCopyWith<$Res> {
  _$PanelsStateCopyWithImpl(this._self, this._then);

  final PanelsState _self;
  final $Res Function(PanelsState) _then;

/// Create a copy of PanelsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? widths = null,}) {
  return _then(_self.copyWith(
widths: null == widths ? _self.widths : widths // ignore: cast_nullable_to_non_nullable
as IMap<PanelSlot, double>,
  ));
}

}



/// @nodoc


class _PanelsState implements PanelsState {
  const _PanelsState({this.widths = const IMapConst<PanelSlot, double>({})});
  

@override@JsonKey() final  IMap<PanelSlot, double> widths;

/// Create a copy of PanelsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PanelsStateCopyWith<_PanelsState> get copyWith => __$PanelsStateCopyWithImpl<_PanelsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PanelsState&&(identical(other.widths, widths) || other.widths == widths));
}


@override
int get hashCode => Object.hash(runtimeType,widths);

@override
String toString() {
  return 'PanelsState(widths: $widths)';
}


}

/// @nodoc
abstract mixin class _$PanelsStateCopyWith<$Res> implements $PanelsStateCopyWith<$Res> {
  factory _$PanelsStateCopyWith(_PanelsState value, $Res Function(_PanelsState) _then) = __$PanelsStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<PanelSlot, double> widths
});




}
/// @nodoc
class __$PanelsStateCopyWithImpl<$Res>
    implements _$PanelsStateCopyWith<$Res> {
  __$PanelsStateCopyWithImpl(this._self, this._then);

  final _PanelsState _self;
  final $Res Function(_PanelsState) _then;

/// Create a copy of PanelsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? widths = null,}) {
  return _then(_PanelsState(
widths: null == widths ? _self.widths : widths // ignore: cast_nullable_to_non_nullable
as IMap<PanelSlot, double>,
  ));
}


}

// dart format on
