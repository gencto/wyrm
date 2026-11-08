// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assistant_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AssistantState {

 String? get draft; ISet<int> get ticked; String get panel; IList<String> get context;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&const DeepCollectionEquality().equals(other.ticked, ticked)&&(identical(other.panel, panel) || other.panel == panel)&&const DeepCollectionEquality().equals(other.context, context));
}


@override
int get hashCode => Object.hash(runtimeType,draft,const DeepCollectionEquality().hash(ticked),panel,const DeepCollectionEquality().hash(context));

@override
String toString() {
  return 'AssistantState(draft: $draft, ticked: $ticked, panel: $panel, context: $context)';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 String? draft, ISet<int> ticked, String panel, IList<String> context
});




}
/// @nodoc
class _$AssistantStateCopyWithImpl<$Res>
    implements $AssistantStateCopyWith<$Res> {
  _$AssistantStateCopyWithImpl(this._self, this._then);

  final AssistantState _self;
  final $Res Function(AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draft = freezed,Object? ticked = null,Object? panel = null,Object? context = null,}) {
  return _then(_self.copyWith(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,ticked: null == ticked ? _self.ticked : ticked // ignore: cast_nullable_to_non_nullable
as ISet<int>,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _AssistantState implements AssistantState {
  const _AssistantState({this.draft, this.ticked = const ISetConst({}), this.panel = 'task', this.context = const IListConst([])});
  

@override final  String? draft;
@override@JsonKey() final  ISet<int> ticked;
@override@JsonKey() final  String panel;
@override@JsonKey() final  IList<String> context;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantStateCopyWith<_AssistantState> get copyWith => __$AssistantStateCopyWithImpl<_AssistantState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.draft, draft) || other.draft == draft)&&const DeepCollectionEquality().equals(other.ticked, ticked)&&(identical(other.panel, panel) || other.panel == panel)&&const DeepCollectionEquality().equals(other.context, context));
}


@override
int get hashCode => Object.hash(runtimeType,draft,const DeepCollectionEquality().hash(ticked),panel,const DeepCollectionEquality().hash(context));

@override
String toString() {
  return 'AssistantState(draft: $draft, ticked: $ticked, panel: $panel, context: $context)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 String? draft, ISet<int> ticked, String panel, IList<String> context
});




}
/// @nodoc
class __$AssistantStateCopyWithImpl<$Res>
    implements _$AssistantStateCopyWith<$Res> {
  __$AssistantStateCopyWithImpl(this._self, this._then);

  final _AssistantState _self;
  final $Res Function(_AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draft = freezed,Object? ticked = null,Object? panel = null,Object? context = null,}) {
  return _then(_AssistantState(
draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as String?,ticked: null == ticked ? _self.ticked : ticked // ignore: cast_nullable_to_non_nullable
as ISet<int>,panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as String,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
