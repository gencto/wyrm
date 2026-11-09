// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quarantine_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuarantineState {

 IMap<String, QuarantineEntry> get table; IList<String> get view; String? get selectedEntry; IMap<String, IList<ParamSpec>> get forms;
/// Create a copy of QuarantineState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuarantineStateCopyWith<QuarantineState> get copyWith => _$QuarantineStateCopyWithImpl<QuarantineState>(this as QuarantineState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuarantineState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedEntry, selectedEntry) || other.selectedEntry == selectedEntry)&&(identical(other.forms, forms) || other.forms == forms));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedEntry,forms);

@override
String toString() {
  return 'QuarantineState(table: $table, view: $view, selectedEntry: $selectedEntry, forms: $forms)';
}


}

/// @nodoc
abstract mixin class $QuarantineStateCopyWith<$Res>  {
  factory $QuarantineStateCopyWith(QuarantineState value, $Res Function(QuarantineState) _then) = _$QuarantineStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, QuarantineEntry> table, IList<String> view, String? selectedEntry, IMap<String, IList<ParamSpec>> forms
});




}
/// @nodoc
class _$QuarantineStateCopyWithImpl<$Res>
    implements $QuarantineStateCopyWith<$Res> {
  _$QuarantineStateCopyWithImpl(this._self, this._then);

  final QuarantineState _self;
  final $Res Function(QuarantineState) _then;

/// Create a copy of QuarantineState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? selectedEntry = freezed,Object? forms = null,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, QuarantineEntry>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedEntry: freezed == selectedEntry ? _self.selectedEntry : selectedEntry // ignore: cast_nullable_to_non_nullable
as String?,forms: null == forms ? _self.forms : forms // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<ParamSpec>>,
  ));
}

}



/// @nodoc


class _QuarantineState implements QuarantineState {
  const _QuarantineState({this.table = const IMapConst({}), this.view = const IListConst([]), this.selectedEntry, this.forms = const IMapConst({})});
  

@override@JsonKey() final  IMap<String, QuarantineEntry> table;
@override@JsonKey() final  IList<String> view;
@override final  String? selectedEntry;
@override@JsonKey() final  IMap<String, IList<ParamSpec>> forms;

/// Create a copy of QuarantineState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuarantineStateCopyWith<_QuarantineState> get copyWith => __$QuarantineStateCopyWithImpl<_QuarantineState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuarantineState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedEntry, selectedEntry) || other.selectedEntry == selectedEntry)&&(identical(other.forms, forms) || other.forms == forms));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedEntry,forms);

@override
String toString() {
  return 'QuarantineState(table: $table, view: $view, selectedEntry: $selectedEntry, forms: $forms)';
}


}

/// @nodoc
abstract mixin class _$QuarantineStateCopyWith<$Res> implements $QuarantineStateCopyWith<$Res> {
  factory _$QuarantineStateCopyWith(_QuarantineState value, $Res Function(_QuarantineState) _then) = __$QuarantineStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, QuarantineEntry> table, IList<String> view, String? selectedEntry, IMap<String, IList<ParamSpec>> forms
});




}
/// @nodoc
class __$QuarantineStateCopyWithImpl<$Res>
    implements _$QuarantineStateCopyWith<$Res> {
  __$QuarantineStateCopyWithImpl(this._self, this._then);

  final _QuarantineState _self;
  final $Res Function(_QuarantineState) _then;

/// Create a copy of QuarantineState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? selectedEntry = freezed,Object? forms = null,}) {
  return _then(_QuarantineState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, QuarantineEntry>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedEntry: freezed == selectedEntry ? _self.selectedEntry : selectedEntry // ignore: cast_nullable_to_non_nullable
as String?,forms: null == forms ? _self.forms : forms // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<ParamSpec>>,
  ));
}


}

// dart format on
