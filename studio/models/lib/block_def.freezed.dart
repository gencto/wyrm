// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'block_def.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlockPort {

 String get name;/// An input: the inner inputs it feeds (`to`); an output: the one inner
/// output it sends (`from`).
 List<PortEnd> get ends;/// An input's default, as JSON; null for none, or a `null` default
/// when [hasDefault].
 Object? get defaultValue;/// The definition wrote a `default`, a `null` one too: written back
/// the same way.
 bool get hasDefault; String? get description;/// The definition wrote the input's `to` as one text, not a list (the
/// spec takes both): written back the same way.
 bool get oneEnd;/// The keys of the port the editor does not read, as JSON, kept for
/// the write back (the block's own are [BlockDef.extra]).
 IMap<String, Object?> get extra;
/// Create a copy of BlockPort
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockPortCopyWith<BlockPort> get copyWith => _$BlockPortCopyWithImpl<BlockPort>(this as BlockPort, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlockPort;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockPort&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.ends, _this.ends)&&const DeepCollectionEquality().equals(other.defaultValue, _this.defaultValue)&&(identical(other.hasDefault, _this.hasDefault) || other.hasDefault == _this.hasDefault)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.oneEnd, _this.oneEnd) || other.oneEnd == _this.oneEnd)&&(identical(other.extra, _this.extra) || other.extra == _this.extra));
}


@override
int get hashCode {
  final _this = this as BlockPort;
  return Object.hash(runtimeType,_this.name,const DeepCollectionEquality().hash(_this.ends),const DeepCollectionEquality().hash(_this.defaultValue),_this.hasDefault,_this.description,_this.oneEnd,_this.extra);
}

@override
String toString() {
  final _this = this as BlockPort;
  return 'BlockPort(name: ${_this.name}, ends: ${_this.ends}, defaultValue: ${_this.defaultValue}, hasDefault: ${_this.hasDefault}, description: ${_this.description}, oneEnd: ${_this.oneEnd}, extra: ${_this.extra})';
}


}

/// @nodoc
abstract mixin class $BlockPortCopyWith<$Res>  {
  factory $BlockPortCopyWith(BlockPort value, $Res Function(BlockPort) _then) = _$BlockPortCopyWithImpl;
@useResult
$Res call({
 String name, List<PortEnd> ends, Object? defaultValue, bool hasDefault, String? description, bool oneEnd, IMap<String, Object?> extra
});




}
/// @nodoc
class _$BlockPortCopyWithImpl<$Res>
    implements $BlockPortCopyWith<$Res> {
  _$BlockPortCopyWithImpl(this._self, this._then);

  final BlockPort _self;
  final $Res Function(BlockPort) _then;

/// Create a copy of BlockPort
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? ends = null,Object? defaultValue = freezed,Object? hasDefault = null,Object? description = freezed,Object? oneEnd = null,Object? extra = null,}) {
  return _then(BlockPort(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ends: null == ends ? _self.ends : ends // ignore: cast_nullable_to_non_nullable
as List<PortEnd>,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue ,hasDefault: null == hasDefault ? _self.hasDefault : hasDefault // ignore: cast_nullable_to_non_nullable
as bool,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,oneEnd: null == oneEnd ? _self.oneEnd : oneEnd // ignore: cast_nullable_to_non_nullable
as bool,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}

}



/// @nodoc


class _BlockPort extends BlockPort {
  const _BlockPort(this.name, { List<PortEnd> ends = const [], this.defaultValue, this.hasDefault = false, this.description, this.oneEnd = false, this.extra = const IMapConst({})}): _ends = ends,super._();
  

@override final  String name;
/// An input: the inner inputs it feeds (`to`); an output: the one inner
/// output it sends (`from`).
 final  List<PortEnd> _ends;
/// An input: the inner inputs it feeds (`to`); an output: the one inner
/// output it sends (`from`).
@override@JsonKey() List<PortEnd> get ends {
  if (_ends is EqualUnmodifiableListView) return _ends;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ends);
}

/// An input's default, as JSON; null for none, or a `null` default
/// when [hasDefault].
@override final  Object? defaultValue;
/// The definition wrote a `default`, a `null` one too: written back
/// the same way.
@override@JsonKey() final  bool hasDefault;
@override final  String? description;
/// The definition wrote the input's `to` as one text, not a list (the
/// spec takes both): written back the same way.
@override@JsonKey() final  bool oneEnd;
/// The keys of the port the editor does not read, as JSON, kept for
/// the write back (the block's own are [BlockDef.extra]).
@override@JsonKey() final  IMap<String, Object?> extra;

/// Create a copy of BlockPort
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlockPortCopyWith<_BlockPort> get copyWith => __$BlockPortCopyWithImpl<_BlockPort>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlockPort&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.ends, _ends)&&const DeepCollectionEquality().equals(other.defaultValue, defaultValue)&&(identical(other.hasDefault, hasDefault) || other.hasDefault == hasDefault)&&(identical(other.description, description) || other.description == description)&&(identical(other.oneEnd, oneEnd) || other.oneEnd == oneEnd)&&(identical(other.extra, extra) || other.extra == extra));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_ends),const DeepCollectionEquality().hash(defaultValue),hasDefault,description,oneEnd,extra);
}

@override
String toString() {
    return 'BlockPort(name: $name, ends: $ends, defaultValue: $defaultValue, hasDefault: $hasDefault, description: $description, oneEnd: $oneEnd, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$BlockPortCopyWith<$Res> implements $BlockPortCopyWith<$Res> {
  factory _$BlockPortCopyWith(_BlockPort value, $Res Function(_BlockPort) _then) = __$BlockPortCopyWithImpl;
@override @useResult
$Res call({
 String name, List<PortEnd> ends, Object? defaultValue, bool hasDefault, String? description, bool oneEnd, IMap<String, Object?> extra
});




}
/// @nodoc
class __$BlockPortCopyWithImpl<$Res>
    implements _$BlockPortCopyWith<$Res> {
  __$BlockPortCopyWithImpl(this._self, this._then);

  final _BlockPort _self;
  final $Res Function(_BlockPort) _then;

/// Create a copy of BlockPort
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? ends = null,Object? defaultValue = freezed,Object? hasDefault = null,Object? description = freezed,Object? oneEnd = null,Object? extra = null,}) {
  return _then(_BlockPort(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ends: null == ends ? _self._ends : ends // ignore: cast_nullable_to_non_nullable
as List<PortEnd>,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue ,hasDefault: null == hasDefault ? _self.hasDefault : hasDefault // ignore: cast_nullable_to_non_nullable
as bool,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,oneEnd: null == oneEnd ? _self.oneEnd : oneEnd // ignore: cast_nullable_to_non_nullable
as bool,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}


}

/// @nodoc
mixin _$BlockDef {

/// Its nodes, edges and layout, read as a flow's (an id-less draft).
 FlowDraft get body; String? get description; List<BlockPort> get inputs; List<BlockPort> get outputs;/// The library version it was copied at; null for a block made in the
/// flow.
 int? get libraryVersion;/// Where its inside draws the inputs block and the outputs block.
 (double, double,)? get inputsAt; (double, double,)? get outputsAt;/// The nodes of [body] its `layout` gave a place, when it was read; the
/// others stand where the editor put them, and only a placed one is
/// written back with its place. Null: every node is placed (a block
/// made or edited in the editor).
 ISet<String>? get placed;/// The definition came with a `layout` (the spec lets it go without):
/// written back with one even when it has no entry. A block made in
/// the editor has one.
 bool get hasLayout;/// The places its `layout` gave, as the definition wrote them (by
/// node id, and the boundary blocks' keys): a place nobody moved is
/// written back as it came, a fraction too.
 IMap<String, (num, num,)> get placesIn;/// The keys of the definition the editor does not read, as JSON, kept
/// for the write back.
 IMap<String, Object?> get extra;
/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockDefCopyWith<BlockDef> get copyWith => _$BlockDefCopyWithImpl<BlockDef>(this as BlockDef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlockDef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockDef&&(identical(other.body, _this.body) || other.body == _this.body)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.inputs, _this.inputs)&&const DeepCollectionEquality().equals(other.outputs, _this.outputs)&&(identical(other.libraryVersion, _this.libraryVersion) || other.libraryVersion == _this.libraryVersion)&&(identical(other.inputsAt, _this.inputsAt) || other.inputsAt == _this.inputsAt)&&(identical(other.outputsAt, _this.outputsAt) || other.outputsAt == _this.outputsAt)&&const DeepCollectionEquality().equals(other.placed, _this.placed)&&(identical(other.hasLayout, _this.hasLayout) || other.hasLayout == _this.hasLayout)&&(identical(other.placesIn, _this.placesIn) || other.placesIn == _this.placesIn)&&(identical(other.extra, _this.extra) || other.extra == _this.extra));
}


@override
int get hashCode {
  final _this = this as BlockDef;
  return Object.hash(runtimeType,_this.body,_this.description,const DeepCollectionEquality().hash(_this.inputs),const DeepCollectionEquality().hash(_this.outputs),_this.libraryVersion,_this.inputsAt,_this.outputsAt,const DeepCollectionEquality().hash(_this.placed),_this.hasLayout,_this.placesIn,_this.extra);
}

@override
String toString() {
  final _this = this as BlockDef;
  return 'BlockDef(body: ${_this.body}, description: ${_this.description}, inputs: ${_this.inputs}, outputs: ${_this.outputs}, libraryVersion: ${_this.libraryVersion}, inputsAt: ${_this.inputsAt}, outputsAt: ${_this.outputsAt}, placed: ${_this.placed}, hasLayout: ${_this.hasLayout}, placesIn: ${_this.placesIn}, extra: ${_this.extra})';
}


}

/// @nodoc
abstract mixin class $BlockDefCopyWith<$Res>  {
  factory $BlockDefCopyWith(BlockDef value, $Res Function(BlockDef) _then) = _$BlockDefCopyWithImpl;
@useResult
$Res call({
 FlowDraft body, String? description, List<BlockPort> inputs, List<BlockPort> outputs, int? libraryVersion, (double, double,)? inputsAt, (double, double,)? outputsAt, ISet<String>? placed, bool hasLayout, IMap<String, (num, num,)> placesIn, IMap<String, Object?> extra
});


$FlowDraftCopyWith<$Res> get body;

}
/// @nodoc
class _$BlockDefCopyWithImpl<$Res>
    implements $BlockDefCopyWith<$Res> {
  _$BlockDefCopyWithImpl(this._self, this._then);

  final BlockDef _self;
  final $Res Function(BlockDef) _then;

/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? body = null,Object? description = freezed,Object? inputs = null,Object? outputs = null,Object? libraryVersion = freezed,Object? inputsAt = freezed,Object? outputsAt = freezed,Object? placed = freezed,Object? hasLayout = null,Object? placesIn = null,Object? extra = null,}) {
  return _then(BlockDef(
body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as FlowDraft,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,inputs: null == inputs ? _self.inputs : inputs // ignore: cast_nullable_to_non_nullable
as List<BlockPort>,outputs: null == outputs ? _self.outputs : outputs // ignore: cast_nullable_to_non_nullable
as List<BlockPort>,libraryVersion: freezed == libraryVersion ? _self.libraryVersion : libraryVersion // ignore: cast_nullable_to_non_nullable
as int?,inputsAt: freezed == inputsAt ? _self.inputsAt : inputsAt // ignore: cast_nullable_to_non_nullable
as (double, double,)?,outputsAt: freezed == outputsAt ? _self.outputsAt : outputsAt // ignore: cast_nullable_to_non_nullable
as (double, double,)?,placed: freezed == placed ? _self.placed : placed // ignore: cast_nullable_to_non_nullable
as ISet<String>?,hasLayout: null == hasLayout ? _self.hasLayout : hasLayout // ignore: cast_nullable_to_non_nullable
as bool,placesIn: null == placesIn ? _self.placesIn : placesIn // ignore: cast_nullable_to_non_nullable
as IMap<String, (num, num,)>,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}
/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res> get body {
  
  return $FlowDraftCopyWith<$Res>(_self.body, (value) {
    return _then(_self.copyWith(body: value));
  });
}
}



/// @nodoc


class _BlockDef extends BlockDef {
  const _BlockDef({required this.body, this.description,  List<BlockPort> inputs = const [],  List<BlockPort> outputs = const [], this.libraryVersion, this.inputsAt, this.outputsAt, this.placed, this.hasLayout = true, this.placesIn = const IMapConst({}), this.extra = const IMapConst({})}): _inputs = inputs,_outputs = outputs,super._();
  

/// Its nodes, edges and layout, read as a flow's (an id-less draft).
@override final  FlowDraft body;
@override final  String? description;
 final  List<BlockPort> _inputs;
@override@JsonKey() List<BlockPort> get inputs {
  if (_inputs is EqualUnmodifiableListView) return _inputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_inputs);
}

 final  List<BlockPort> _outputs;
@override@JsonKey() List<BlockPort> get outputs {
  if (_outputs is EqualUnmodifiableListView) return _outputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputs);
}

/// The library version it was copied at; null for a block made in the
/// flow.
@override final  int? libraryVersion;
/// Where its inside draws the inputs block and the outputs block.
@override final  (double, double,)? inputsAt;
@override final  (double, double,)? outputsAt;
/// The nodes of [body] its `layout` gave a place, when it was read; the
/// others stand where the editor put them, and only a placed one is
/// written back with its place. Null: every node is placed (a block
/// made or edited in the editor).
@override final  ISet<String>? placed;
/// The definition came with a `layout` (the spec lets it go without):
/// written back with one even when it has no entry. A block made in
/// the editor has one.
@override@JsonKey() final  bool hasLayout;
/// The places its `layout` gave, as the definition wrote them (by
/// node id, and the boundary blocks' keys): a place nobody moved is
/// written back as it came, a fraction too.
@override@JsonKey() final  IMap<String, (num, num,)> placesIn;
/// The keys of the definition the editor does not read, as JSON, kept
/// for the write back.
@override@JsonKey() final  IMap<String, Object?> extra;

/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlockDefCopyWith<_BlockDef> get copyWith => __$BlockDefCopyWithImpl<_BlockDef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlockDef&&(identical(other.body, body) || other.body == body)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.inputs, _inputs)&&const DeepCollectionEquality().equals(other.outputs, _outputs)&&(identical(other.libraryVersion, libraryVersion) || other.libraryVersion == libraryVersion)&&(identical(other.inputsAt, inputsAt) || other.inputsAt == inputsAt)&&(identical(other.outputsAt, outputsAt) || other.outputsAt == outputsAt)&&const DeepCollectionEquality().equals(other.placed, placed)&&(identical(other.hasLayout, hasLayout) || other.hasLayout == hasLayout)&&(identical(other.placesIn, placesIn) || other.placesIn == placesIn)&&(identical(other.extra, extra) || other.extra == extra));
}


@override
int get hashCode {
    return Object.hash(runtimeType,body,description,const DeepCollectionEquality().hash(_inputs),const DeepCollectionEquality().hash(_outputs),libraryVersion,inputsAt,outputsAt,const DeepCollectionEquality().hash(placed),hasLayout,placesIn,extra);
}

@override
String toString() {
    return 'BlockDef(body: $body, description: $description, inputs: $inputs, outputs: $outputs, libraryVersion: $libraryVersion, inputsAt: $inputsAt, outputsAt: $outputsAt, placed: $placed, hasLayout: $hasLayout, placesIn: $placesIn, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$BlockDefCopyWith<$Res> implements $BlockDefCopyWith<$Res> {
  factory _$BlockDefCopyWith(_BlockDef value, $Res Function(_BlockDef) _then) = __$BlockDefCopyWithImpl;
@override @useResult
$Res call({
 FlowDraft body, String? description, List<BlockPort> inputs, List<BlockPort> outputs, int? libraryVersion, (double, double,)? inputsAt, (double, double,)? outputsAt, ISet<String>? placed, bool hasLayout, IMap<String, (num, num,)> placesIn, IMap<String, Object?> extra
});


@override $FlowDraftCopyWith<$Res> get body;

}
/// @nodoc
class __$BlockDefCopyWithImpl<$Res>
    implements _$BlockDefCopyWith<$Res> {
  __$BlockDefCopyWithImpl(this._self, this._then);

  final _BlockDef _self;
  final $Res Function(_BlockDef) _then;

/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? body = null,Object? description = freezed,Object? inputs = null,Object? outputs = null,Object? libraryVersion = freezed,Object? inputsAt = freezed,Object? outputsAt = freezed,Object? placed = freezed,Object? hasLayout = null,Object? placesIn = null,Object? extra = null,}) {
  return _then(_BlockDef(
body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as FlowDraft,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,inputs: null == inputs ? _self._inputs : inputs // ignore: cast_nullable_to_non_nullable
as List<BlockPort>,outputs: null == outputs ? _self._outputs : outputs // ignore: cast_nullable_to_non_nullable
as List<BlockPort>,libraryVersion: freezed == libraryVersion ? _self.libraryVersion : libraryVersion // ignore: cast_nullable_to_non_nullable
as int?,inputsAt: freezed == inputsAt ? _self.inputsAt : inputsAt // ignore: cast_nullable_to_non_nullable
as (double, double,)?,outputsAt: freezed == outputsAt ? _self.outputsAt : outputsAt // ignore: cast_nullable_to_non_nullable
as (double, double,)?,placed: freezed == placed ? _self.placed : placed // ignore: cast_nullable_to_non_nullable
as ISet<String>?,hasLayout: null == hasLayout ? _self.hasLayout : hasLayout // ignore: cast_nullable_to_non_nullable
as bool,placesIn: null == placesIn ? _self.placesIn : placesIn // ignore: cast_nullable_to_non_nullable
as IMap<String, (num, num,)>,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,
  ));
}

/// Create a copy of BlockDef
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlowDraftCopyWith<$Res> get body {
  
  return $FlowDraftCopyWith<$Res>(_self.body, (value) {
    return _then(_self.copyWith(body: value));
  });
}
}

// dart format on
