// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskRow {

/// The full node key; what goes into `ask {context}`.
 String get key; String get label; String get detail;
/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskRowCopyWith<TaskRow> get copyWith => _$TaskRowCopyWithImpl<TaskRow>(this as TaskRow, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskRow;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskRow&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as TaskRow;
  return Object.hash(runtimeType,_this.key,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as TaskRow;
  return 'TaskRow(key: ${_this.key}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $TaskRowCopyWith<$Res>  {
  factory $TaskRowCopyWith(TaskRow value, $Res Function(TaskRow) _then) = _$TaskRowCopyWithImpl;
@useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class _$TaskRowCopyWithImpl<$Res>
    implements $TaskRowCopyWith<$Res> {
  _$TaskRowCopyWithImpl(this._self, this._then);

  final TaskRow _self;
  final $Res Function(TaskRow) _then;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(TaskRow(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskRow].
extension TaskRowPatterns on TaskRow {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskRow value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskRow() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskRow value)  $default,){
final _that = this;
switch (_that) {
case _TaskRow():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskRow value)?  $default,){
final _that = this;
switch (_that) {
case _TaskRow() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String label,  String detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskRow() when $default != null:
return $default(_that.key,_that.label,_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String label,  String detail)  $default,) {final _that = this;
switch (_that) {
case _TaskRow():
return $default(_that.key,_that.label,_that.detail);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String label,  String detail)?  $default,) {final _that = this;
switch (_that) {
case _TaskRow() when $default != null:
return $default(_that.key,_that.label,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class _TaskRow extends TaskRow {
  const _TaskRow({required this.key, required this.label, this.detail = ''}): super._();
  

/// The full node key; what goes into `ask {context}`.
@override final  String key;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskRowCopyWith<_TaskRow> get copyWith => __$TaskRowCopyWithImpl<_TaskRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskRow&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,label,detail);
}

@override
String toString() {
    return 'TaskRow(key: $key, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$TaskRowCopyWith<$Res> implements $TaskRowCopyWith<$Res> {
  factory _$TaskRowCopyWith(_TaskRow value, $Res Function(_TaskRow) _then) = __$TaskRowCopyWithImpl;
@override @useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class __$TaskRowCopyWithImpl<$Res>
    implements _$TaskRowCopyWith<$Res> {
  __$TaskRowCopyWithImpl(this._self, this._then);

  final _TaskRow _self;
  final $Res Function(_TaskRow) _then;

/// Create a copy of TaskRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(_TaskRow(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TaskSuggestion {

 String get id; String get label; String get detail;/// How many changes the model expects the follow-up to plan; 0: nothing
/// changes. The model's guess, for the tag on the card.
 int get changes;/// The plan step (`n`, from 1) this is a fix for; null: about the task.
 int? get step; List<TaskRow> get rows;
/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskSuggestionCopyWith<TaskSuggestion> get copyWith => _$TaskSuggestionCopyWithImpl<TaskSuggestion>(this as TaskSuggestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskSuggestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskSuggestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.changes, _this.changes) || other.changes == _this.changes)&&(identical(other.step, _this.step) || other.step == _this.step)&&const DeepCollectionEquality().equals(other.rows, _this.rows));
}


@override
int get hashCode {
  final _this = this as TaskSuggestion;
  return Object.hash(runtimeType,_this.id,_this.label,_this.detail,_this.changes,_this.step,const DeepCollectionEquality().hash(_this.rows));
}

@override
String toString() {
  final _this = this as TaskSuggestion;
  return 'TaskSuggestion(id: ${_this.id}, label: ${_this.label}, detail: ${_this.detail}, changes: ${_this.changes}, step: ${_this.step}, rows: ${_this.rows})';
}


}

/// @nodoc
abstract mixin class $TaskSuggestionCopyWith<$Res>  {
  factory $TaskSuggestionCopyWith(TaskSuggestion value, $Res Function(TaskSuggestion) _then) = _$TaskSuggestionCopyWithImpl;
@useResult
$Res call({
 String id, String label, String detail, int changes, int? step, List<TaskRow> rows
});




}
/// @nodoc
class _$TaskSuggestionCopyWithImpl<$Res>
    implements $TaskSuggestionCopyWith<$Res> {
  _$TaskSuggestionCopyWithImpl(this._self, this._then);

  final TaskSuggestion _self;
  final $Res Function(TaskSuggestion) _then;

/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? detail = null,Object? changes = null,Object? step = freezed,Object? rows = null,}) {
  return _then(TaskSuggestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as int,step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int?,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as List<TaskRow>,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskSuggestion].
extension TaskSuggestionPatterns on TaskSuggestion {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskSuggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskSuggestion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskSuggestion value)  $default,){
final _that = this;
switch (_that) {
case _TaskSuggestion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskSuggestion value)?  $default,){
final _that = this;
switch (_that) {
case _TaskSuggestion() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String detail,  int changes,  int? step,  List<TaskRow> rows)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskSuggestion() when $default != null:
return $default(_that.id,_that.label,_that.detail,_that.changes,_that.step,_that.rows);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String detail,  int changes,  int? step,  List<TaskRow> rows)  $default,) {final _that = this;
switch (_that) {
case _TaskSuggestion():
return $default(_that.id,_that.label,_that.detail,_that.changes,_that.step,_that.rows);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String detail,  int changes,  int? step,  List<TaskRow> rows)?  $default,) {final _that = this;
switch (_that) {
case _TaskSuggestion() when $default != null:
return $default(_that.id,_that.label,_that.detail,_that.changes,_that.step,_that.rows);case _:
  return null;

}
}

}

/// @nodoc


class _TaskSuggestion extends TaskSuggestion {
  const _TaskSuggestion({required this.id, required this.label, this.detail = '', this.changes = 0, this.step,  List<TaskRow> rows = const <TaskRow>[]}): _rows = rows,super._();
  

@override final  String id;
@override final  String label;
@override@JsonKey() final  String detail;
/// How many changes the model expects the follow-up to plan; 0: nothing
/// changes. The model's guess, for the tag on the card.
@override@JsonKey() final  int changes;
/// The plan step (`n`, from 1) this is a fix for; null: about the task.
@override final  int? step;
 final  List<TaskRow> _rows;
@override@JsonKey() List<TaskRow> get rows {
  if (_rows is EqualUnmodifiableListView) return _rows;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rows);
}


/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskSuggestionCopyWith<_TaskSuggestion> get copyWith => __$TaskSuggestionCopyWithImpl<_TaskSuggestion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskSuggestion&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.changes, changes) || other.changes == changes)&&(identical(other.step, step) || other.step == step)&&const DeepCollectionEquality().equals(other.rows, _rows));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,label,detail,changes,step,const DeepCollectionEquality().hash(_rows));
}

@override
String toString() {
    return 'TaskSuggestion(id: $id, label: $label, detail: $detail, changes: $changes, step: $step, rows: $rows)';
}


}

/// @nodoc
abstract mixin class _$TaskSuggestionCopyWith<$Res> implements $TaskSuggestionCopyWith<$Res> {
  factory _$TaskSuggestionCopyWith(_TaskSuggestion value, $Res Function(_TaskSuggestion) _then) = __$TaskSuggestionCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String detail, int changes, int? step, List<TaskRow> rows
});




}
/// @nodoc
class __$TaskSuggestionCopyWithImpl<$Res>
    implements _$TaskSuggestionCopyWith<$Res> {
  __$TaskSuggestionCopyWithImpl(this._self, this._then);

  final _TaskSuggestion _self;
  final $Res Function(_TaskSuggestion) _then;

/// Create a copy of TaskSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? detail = null,Object? changes = null,Object? step = freezed,Object? rows = null,}) {
  return _then(_TaskSuggestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as int,step: freezed == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int?,rows: null == rows ? _self._rows : rows // ignore: cast_nullable_to_non_nullable
as List<TaskRow>,
  ));
}


}

/// @nodoc
mixin _$TaskFinding {

/// The full node key.
 String get key; String get label; String get detail;
/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskFindingCopyWith<TaskFinding> get copyWith => _$TaskFindingCopyWithImpl<TaskFinding>(this as TaskFinding, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TaskFinding;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskFinding&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as TaskFinding;
  return Object.hash(runtimeType,_this.key,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as TaskFinding;
  return 'TaskFinding(key: ${_this.key}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $TaskFindingCopyWith<$Res>  {
  factory $TaskFindingCopyWith(TaskFinding value, $Res Function(TaskFinding) _then) = _$TaskFindingCopyWithImpl;
@useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class _$TaskFindingCopyWithImpl<$Res>
    implements $TaskFindingCopyWith<$Res> {
  _$TaskFindingCopyWithImpl(this._self, this._then);

  final TaskFinding _self;
  final $Res Function(TaskFinding) _then;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(TaskFinding(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskFinding].
extension TaskFindingPatterns on TaskFinding {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskFinding value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskFinding() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskFinding value)  $default,){
final _that = this;
switch (_that) {
case _TaskFinding():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskFinding value)?  $default,){
final _that = this;
switch (_that) {
case _TaskFinding() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String label,  String detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskFinding() when $default != null:
return $default(_that.key,_that.label,_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String label,  String detail)  $default,) {final _that = this;
switch (_that) {
case _TaskFinding():
return $default(_that.key,_that.label,_that.detail);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String label,  String detail)?  $default,) {final _that = this;
switch (_that) {
case _TaskFinding() when $default != null:
return $default(_that.key,_that.label,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class _TaskFinding extends TaskFinding {
  const _TaskFinding({required this.key, required this.label, this.detail = ''}): super._();
  

/// The full node key.
@override final  String key;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskFindingCopyWith<_TaskFinding> get copyWith => __$TaskFindingCopyWithImpl<_TaskFinding>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskFinding&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,label,detail);
}

@override
String toString() {
    return 'TaskFinding(key: $key, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$TaskFindingCopyWith<$Res> implements $TaskFindingCopyWith<$Res> {
  factory _$TaskFindingCopyWith(_TaskFinding value, $Res Function(_TaskFinding) _then) = __$TaskFindingCopyWithImpl;
@override @useResult
$Res call({
 String key, String label, String detail
});




}
/// @nodoc
class __$TaskFindingCopyWithImpl<$Res>
    implements _$TaskFindingCopyWith<$Res> {
  __$TaskFindingCopyWithImpl(this._self, this._then);

  final _TaskFinding _self;
  final $Res Function(_TaskFinding) _then;

/// Create a copy of TaskFinding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,Object? detail = null,}) {
  return _then(_TaskFinding(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AgentChoice {

 String get id; String get label; String get detail;
/// Create a copy of AgentChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentChoiceCopyWith<AgentChoice> get copyWith => _$AgentChoiceCopyWithImpl<AgentChoice>(this as AgentChoice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentChoice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentChoice&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as AgentChoice;
  return Object.hash(runtimeType,_this.id,_this.label,_this.detail);
}

@override
String toString() {
  final _this = this as AgentChoice;
  return 'AgentChoice(id: ${_this.id}, label: ${_this.label}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $AgentChoiceCopyWith<$Res>  {
  factory $AgentChoiceCopyWith(AgentChoice value, $Res Function(AgentChoice) _then) = _$AgentChoiceCopyWithImpl;
@useResult
$Res call({
 String id, String label, String detail
});




}
/// @nodoc
class _$AgentChoiceCopyWithImpl<$Res>
    implements $AgentChoiceCopyWith<$Res> {
  _$AgentChoiceCopyWithImpl(this._self, this._then);

  final AgentChoice _self;
  final $Res Function(AgentChoice) _then;

/// Create a copy of AgentChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? detail = null,}) {
  return _then(AgentChoice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentChoice].
extension AgentChoicePatterns on AgentChoice {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentChoice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentChoice() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentChoice value)  $default,){
final _that = this;
switch (_that) {
case _AgentChoice():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentChoice value)?  $default,){
final _that = this;
switch (_that) {
case _AgentChoice() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentChoice() when $default != null:
return $default(_that.id,_that.label,_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String detail)  $default,) {final _that = this;
switch (_that) {
case _AgentChoice():
return $default(_that.id,_that.label,_that.detail);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String detail)?  $default,) {final _that = this;
switch (_that) {
case _AgentChoice() when $default != null:
return $default(_that.id,_that.label,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class _AgentChoice implements AgentChoice {
  const _AgentChoice({required this.id, required this.label, this.detail = ''});
  

@override final  String id;
@override final  String label;
@override@JsonKey() final  String detail;

/// Create a copy of AgentChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentChoiceCopyWith<_AgentChoice> get copyWith => __$AgentChoiceCopyWithImpl<_AgentChoice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentChoice&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,label,detail);
}

@override
String toString() {
    return 'AgentChoice(id: $id, label: $label, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$AgentChoiceCopyWith<$Res> implements $AgentChoiceCopyWith<$Res> {
  factory _$AgentChoiceCopyWith(_AgentChoice value, $Res Function(_AgentChoice) _then) = __$AgentChoiceCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String detail
});




}
/// @nodoc
class __$AgentChoiceCopyWithImpl<$Res>
    implements _$AgentChoiceCopyWith<$Res> {
  __$AgentChoiceCopyWithImpl(this._self, this._then);

  final _AgentChoice _self;
  final $Res Function(_AgentChoice) _then;

/// Create a copy of AgentChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? detail = null,}) {
  return _then(_AgentChoice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AgentQuestion {

/// `q1`, `q2`, …: unique in the task.
 String get id; String get text; List<AgentChoice> get options;/// More than one option may be picked.
 bool get multiple;/// The person may answer in their own words.
 bool get freeText;/// The answer given: the picked option ids or the person's words.
 AgentAnswer? get answer;
/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentQuestionCopyWith<AgentQuestion> get copyWith => _$AgentQuestionCopyWithImpl<AgentQuestion>(this as AgentQuestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentQuestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentQuestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.options, _this.options)&&(identical(other.multiple, _this.multiple) || other.multiple == _this.multiple)&&(identical(other.freeText, _this.freeText) || other.freeText == _this.freeText)&&(identical(other.answer, _this.answer) || other.answer == _this.answer));
}


@override
int get hashCode {
  final _this = this as AgentQuestion;
  return Object.hash(runtimeType,_this.id,_this.text,const DeepCollectionEquality().hash(_this.options),_this.multiple,_this.freeText,_this.answer);
}

@override
String toString() {
  final _this = this as AgentQuestion;
  return 'AgentQuestion(id: ${_this.id}, text: ${_this.text}, options: ${_this.options}, multiple: ${_this.multiple}, freeText: ${_this.freeText}, answer: ${_this.answer})';
}


}

/// @nodoc
abstract mixin class $AgentQuestionCopyWith<$Res>  {
  factory $AgentQuestionCopyWith(AgentQuestion value, $Res Function(AgentQuestion) _then) = _$AgentQuestionCopyWithImpl;
@useResult
$Res call({
 String id, String text, List<AgentChoice> options, bool multiple, bool freeText, AgentAnswer? answer
});


$AgentAnswerCopyWith<$Res>? get answer;

}
/// @nodoc
class _$AgentQuestionCopyWithImpl<$Res>
    implements $AgentQuestionCopyWith<$Res> {
  _$AgentQuestionCopyWithImpl(this._self, this._then);

  final AgentQuestion _self;
  final $Res Function(AgentQuestion) _then;

/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? options = null,Object? multiple = null,Object? freeText = null,Object? answer = freezed,}) {
  return _then(AgentQuestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<AgentChoice>,multiple: null == multiple ? _self.multiple : multiple // ignore: cast_nullable_to_non_nullable
as bool,freeText: null == freeText ? _self.freeText : freeText // ignore: cast_nullable_to_non_nullable
as bool,answer: freezed == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as AgentAnswer?,
  ));
}
/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentAnswerCopyWith<$Res>? get answer {
    if (_self.answer == null) {
    return null;
  }

  return $AgentAnswerCopyWith<$Res>(_self.answer!, (value) {
    return _then(_self.copyWith(answer: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentQuestion].
extension AgentQuestionPatterns on AgentQuestion {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentQuestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentQuestion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentQuestion value)  $default,){
final _that = this;
switch (_that) {
case _AgentQuestion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentQuestion value)?  $default,){
final _that = this;
switch (_that) {
case _AgentQuestion() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String text,  List<AgentChoice> options,  bool multiple,  bool freeText,  AgentAnswer? answer)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentQuestion() when $default != null:
return $default(_that.id,_that.text,_that.options,_that.multiple,_that.freeText,_that.answer);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String text,  List<AgentChoice> options,  bool multiple,  bool freeText,  AgentAnswer? answer)  $default,) {final _that = this;
switch (_that) {
case _AgentQuestion():
return $default(_that.id,_that.text,_that.options,_that.multiple,_that.freeText,_that.answer);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String text,  List<AgentChoice> options,  bool multiple,  bool freeText,  AgentAnswer? answer)?  $default,) {final _that = this;
switch (_that) {
case _AgentQuestion() when $default != null:
return $default(_that.id,_that.text,_that.options,_that.multiple,_that.freeText,_that.answer);case _:
  return null;

}
}

}

/// @nodoc


class _AgentQuestion implements AgentQuestion {
  const _AgentQuestion({required this.id, required this.text,  List<AgentChoice> options = const <AgentChoice>[], this.multiple = false, this.freeText = false, this.answer}): _options = options;
  

/// `q1`, `q2`, …: unique in the task.
@override final  String id;
@override final  String text;
 final  List<AgentChoice> _options;
@override@JsonKey() List<AgentChoice> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

/// More than one option may be picked.
@override@JsonKey() final  bool multiple;
/// The person may answer in their own words.
@override@JsonKey() final  bool freeText;
/// The answer given: the picked option ids or the person's words.
@override final  AgentAnswer? answer;

/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentQuestionCopyWith<_AgentQuestion> get copyWith => __$AgentQuestionCopyWithImpl<_AgentQuestion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentQuestion&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other.options, _options)&&(identical(other.multiple, multiple) || other.multiple == multiple)&&(identical(other.freeText, freeText) || other.freeText == freeText)&&(identical(other.answer, answer) || other.answer == answer));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,text,const DeepCollectionEquality().hash(_options),multiple,freeText,answer);
}

@override
String toString() {
    return 'AgentQuestion(id: $id, text: $text, options: $options, multiple: $multiple, freeText: $freeText, answer: $answer)';
}


}

/// @nodoc
abstract mixin class _$AgentQuestionCopyWith<$Res> implements $AgentQuestionCopyWith<$Res> {
  factory _$AgentQuestionCopyWith(_AgentQuestion value, $Res Function(_AgentQuestion) _then) = __$AgentQuestionCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, List<AgentChoice> options, bool multiple, bool freeText, AgentAnswer? answer
});


@override $AgentAnswerCopyWith<$Res>? get answer;

}
/// @nodoc
class __$AgentQuestionCopyWithImpl<$Res>
    implements _$AgentQuestionCopyWith<$Res> {
  __$AgentQuestionCopyWithImpl(this._self, this._then);

  final _AgentQuestion _self;
  final $Res Function(_AgentQuestion) _then;

/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? options = null,Object? multiple = null,Object? freeText = null,Object? answer = freezed,}) {
  return _then(_AgentQuestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<AgentChoice>,multiple: null == multiple ? _self.multiple : multiple // ignore: cast_nullable_to_non_nullable
as bool,freeText: null == freeText ? _self.freeText : freeText // ignore: cast_nullable_to_non_nullable
as bool,answer: freezed == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as AgentAnswer?,
  ));
}

/// Create a copy of AgentQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentAnswerCopyWith<$Res>? get answer {
    if (_self.answer == null) {
    return null;
  }

  return $AgentAnswerCopyWith<$Res>(_self.answer!, (value) {
    return _then(_self.copyWith(answer: value));
  });
}
}

/// @nodoc
mixin _$AgentAnswer {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentAnswer);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AgentAnswer()';
}


}

/// @nodoc
class $AgentAnswerCopyWith<$Res>  {
$AgentAnswerCopyWith(AgentAnswer _, $Res Function(AgentAnswer) __);
}


/// Adds pattern-matching-related methods to [AgentAnswer].
extension AgentAnswerPatterns on AgentAnswer {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentAnswerOptions value)?  options,TResult Function( AgentAnswerText value)?  text,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentAnswerOptions() when options != null:
return options(_that);case AgentAnswerText() when text != null:
return text(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentAnswerOptions value)  options,required TResult Function( AgentAnswerText value)  text,}){
final _that = this;
switch (_that) {
case AgentAnswerOptions():
return options(_that);case AgentAnswerText():
return text(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentAnswerOptions value)?  options,TResult? Function( AgentAnswerText value)?  text,}){
final _that = this;
switch (_that) {
case AgentAnswerOptions() when options != null:
return options(_that);case AgentAnswerText() when text != null:
return text(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<String> ids)?  options,TResult Function( String text)?  text,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentAnswerOptions() when options != null:
return options(_that.ids);case AgentAnswerText() when text != null:
return text(_that.text);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<String> ids)  options,required TResult Function( String text)  text,}) {final _that = this;
switch (_that) {
case AgentAnswerOptions():
return options(_that.ids);case AgentAnswerText():
return text(_that.text);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<String> ids)?  options,TResult? Function( String text)?  text,}) {final _that = this;
switch (_that) {
case AgentAnswerOptions() when options != null:
return options(_that.ids);case AgentAnswerText() when text != null:
return text(_that.text);case _:
  return null;

}
}

}

/// @nodoc


class AgentAnswerOptions extends AgentAnswer {
  const AgentAnswerOptions( List<String> ids): _ids = ids,super._();
  

 final  List<String> _ids;
 List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}


/// Create a copy of AgentAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentAnswerOptionsCopyWith<AgentAnswerOptions> get copyWith => _$AgentAnswerOptionsCopyWithImpl<AgentAnswerOptions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentAnswerOptions&&const DeepCollectionEquality().equals(other.ids, _ids));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_ids));
}

@override
String toString() {
    return 'AgentAnswer.options(ids: $ids)';
}


}

/// @nodoc
abstract mixin class $AgentAnswerOptionsCopyWith<$Res> implements $AgentAnswerCopyWith<$Res> {
  factory $AgentAnswerOptionsCopyWith(AgentAnswerOptions value, $Res Function(AgentAnswerOptions) _then) = _$AgentAnswerOptionsCopyWithImpl;
@useResult
$Res call({
 List<String> ids
});




}
/// @nodoc
class _$AgentAnswerOptionsCopyWithImpl<$Res>
    implements $AgentAnswerOptionsCopyWith<$Res> {
  _$AgentAnswerOptionsCopyWithImpl(this._self, this._then);

  final AgentAnswerOptions _self;
  final $Res Function(AgentAnswerOptions) _then;

/// Create a copy of AgentAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ids = null,}) {
  return _then(AgentAnswerOptions(
null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class AgentAnswerText extends AgentAnswer {
  const AgentAnswerText(this.text): super._();
  

 final  String text;

/// Create a copy of AgentAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentAnswerTextCopyWith<AgentAnswerText> get copyWith => _$AgentAnswerTextCopyWithImpl<AgentAnswerText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentAnswerText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'AgentAnswer.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $AgentAnswerTextCopyWith<$Res> implements $AgentAnswerCopyWith<$Res> {
  factory $AgentAnswerTextCopyWith(AgentAnswerText value, $Res Function(AgentAnswerText) _then) = _$AgentAnswerTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AgentAnswerTextCopyWithImpl<$Res>
    implements $AgentAnswerTextCopyWith<$Res> {
  _$AgentAnswerTextCopyWithImpl(this._self, this._then);

  final AgentAnswerText _self;
  final $Res Function(AgentAnswerText) _then;

/// Create a copy of AgentAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AgentAnswerText(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AgentStepResult {

 AgentStepStatus get status;/// The responder's answer in short, its refusal, or why it was skipped.
 String get message;/// When the step ended, seconds since the Unix epoch (0: not told).
 int get time;
/// Create a copy of AgentStepResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentStepResultCopyWith<AgentStepResult> get copyWith => _$AgentStepResultCopyWithImpl<AgentStepResult>(this as AgentStepResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentStepResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentStepResult&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.time, _this.time) || other.time == _this.time));
}


@override
int get hashCode {
  final _this = this as AgentStepResult;
  return Object.hash(runtimeType,_this.status,_this.message,_this.time);
}

@override
String toString() {
  final _this = this as AgentStepResult;
  return 'AgentStepResult(status: ${_this.status}, message: ${_this.message}, time: ${_this.time})';
}


}

/// @nodoc
abstract mixin class $AgentStepResultCopyWith<$Res>  {
  factory $AgentStepResultCopyWith(AgentStepResult value, $Res Function(AgentStepResult) _then) = _$AgentStepResultCopyWithImpl;
@useResult
$Res call({
 AgentStepStatus status, String message, int time
});




}
/// @nodoc
class _$AgentStepResultCopyWithImpl<$Res>
    implements $AgentStepResultCopyWith<$Res> {
  _$AgentStepResultCopyWithImpl(this._self, this._then);

  final AgentStepResult _self;
  final $Res Function(AgentStepResult) _then;

/// Create a copy of AgentStepResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? message = null,Object? time = null,}) {
  return _then(AgentStepResult(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AgentStepStatus,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentStepResult].
extension AgentStepResultPatterns on AgentStepResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentStepResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentStepResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentStepResult value)  $default,){
final _that = this;
switch (_that) {
case _AgentStepResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentStepResult value)?  $default,){
final _that = this;
switch (_that) {
case _AgentStepResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AgentStepStatus status,  String message,  int time)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentStepResult() when $default != null:
return $default(_that.status,_that.message,_that.time);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AgentStepStatus status,  String message,  int time)  $default,) {final _that = this;
switch (_that) {
case _AgentStepResult():
return $default(_that.status,_that.message,_that.time);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AgentStepStatus status,  String message,  int time)?  $default,) {final _that = this;
switch (_that) {
case _AgentStepResult() when $default != null:
return $default(_that.status,_that.message,_that.time);case _:
  return null;

}
}

}

/// @nodoc


class _AgentStepResult implements AgentStepResult {
  const _AgentStepResult({required this.status, this.message = '', this.time = 0});
  

@override final  AgentStepStatus status;
/// The responder's answer in short, its refusal, or why it was skipped.
@override@JsonKey() final  String message;
/// When the step ended, seconds since the Unix epoch (0: not told).
@override@JsonKey() final  int time;

/// Create a copy of AgentStepResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentStepResultCopyWith<_AgentStepResult> get copyWith => __$AgentStepResultCopyWithImpl<_AgentStepResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentStepResult&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message)&&(identical(other.time, time) || other.time == time));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,message,time);
}

@override
String toString() {
    return 'AgentStepResult(status: $status, message: $message, time: $time)';
}


}

/// @nodoc
abstract mixin class _$AgentStepResultCopyWith<$Res> implements $AgentStepResultCopyWith<$Res> {
  factory _$AgentStepResultCopyWith(_AgentStepResult value, $Res Function(_AgentStepResult) _then) = __$AgentStepResultCopyWithImpl;
@override @useResult
$Res call({
 AgentStepStatus status, String message, int time
});




}
/// @nodoc
class __$AgentStepResultCopyWithImpl<$Res>
    implements _$AgentStepResultCopyWith<$Res> {
  __$AgentStepResultCopyWithImpl(this._self, this._then);

  final _AgentStepResult _self;
  final $Res Function(_AgentStepResult) _then;

/// Create a copy of AgentStepResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = null,Object? time = null,}) {
  return _then(_AgentStepResult(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as AgentStepStatus,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AgentPlanStep {

/// The step's number, from 1.
 int get n; AgentStepKind get kind;/// The full node key; null for [AgentStepKind.sleep].
 String? get node;/// `set`: the value to write.
 Value? get value;/// `invoke`: the action and its arguments.
 String? get action; Value? get args;/// `wait`/`expect`: how long to wait; `sleep`: how long to sleep (s).
 double? get seconds;/// `expect`: the value to see, or the range, or any change.
 Value? get equals; double? get min; double? get max; bool get changes;/// The level the step needs.
 Perm get level;/// The steps (`n`) this one runs after.
 List<int> get after;/// It needs a person's approval (the bar of now).
 bool get approval; AgentStepCheck get check;/// The link's own finding about the step.
 String? get warn;/// The model's words about a risk.
 String? get modelWarn; String? get reason; AgentStepResult? get result;
/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentPlanStepCopyWith<AgentPlanStep> get copyWith => _$AgentPlanStepCopyWithImpl<AgentPlanStep>(this as AgentPlanStep, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentPlanStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentPlanStep&&(identical(other.n, _this.n) || other.n == _this.n)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.node, _this.node) || other.node == _this.node)&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.args, _this.args) || other.args == _this.args)&&(identical(other.seconds, _this.seconds) || other.seconds == _this.seconds)&&(identical(other.equals, _this.equals) || other.equals == _this.equals)&&(identical(other.min, _this.min) || other.min == _this.min)&&(identical(other.max, _this.max) || other.max == _this.max)&&(identical(other.changes, _this.changes) || other.changes == _this.changes)&&(identical(other.level, _this.level) || other.level == _this.level)&&const DeepCollectionEquality().equals(other.after, _this.after)&&(identical(other.approval, _this.approval) || other.approval == _this.approval)&&(identical(other.check, _this.check) || other.check == _this.check)&&(identical(other.warn, _this.warn) || other.warn == _this.warn)&&(identical(other.modelWarn, _this.modelWarn) || other.modelWarn == _this.modelWarn)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as AgentPlanStep;
  return Object.hashAll([runtimeType,_this.n,_this.kind,_this.node,_this.value,_this.action,_this.args,_this.seconds,_this.equals,_this.min,_this.max,_this.changes,_this.level,const DeepCollectionEquality().hash(_this.after),_this.approval,_this.check,_this.warn,_this.modelWarn,_this.reason,_this.result]);
}

@override
String toString() {
  final _this = this as AgentPlanStep;
  return 'AgentPlanStep(n: ${_this.n}, kind: ${_this.kind}, node: ${_this.node}, value: ${_this.value}, action: ${_this.action}, args: ${_this.args}, seconds: ${_this.seconds}, equals: ${_this.equals}, min: ${_this.min}, max: ${_this.max}, changes: ${_this.changes}, level: ${_this.level}, after: ${_this.after}, approval: ${_this.approval}, check: ${_this.check}, warn: ${_this.warn}, modelWarn: ${_this.modelWarn}, reason: ${_this.reason}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $AgentPlanStepCopyWith<$Res>  {
  factory $AgentPlanStepCopyWith(AgentPlanStep value, $Res Function(AgentPlanStep) _then) = _$AgentPlanStepCopyWithImpl;
@useResult
$Res call({
 int n, AgentStepKind kind, String? node, Value? value, String? action, Value? args, double? seconds, Value? equals, double? min, double? max, bool changes, Perm level, List<int> after, bool approval, AgentStepCheck check, String? warn, String? modelWarn, String? reason, AgentStepResult? result
});


$AgentStepResultCopyWith<$Res>? get result;

}
/// @nodoc
class _$AgentPlanStepCopyWithImpl<$Res>
    implements $AgentPlanStepCopyWith<$Res> {
  _$AgentPlanStepCopyWithImpl(this._self, this._then);

  final AgentPlanStep _self;
  final $Res Function(AgentPlanStep) _then;

/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? n = null,Object? kind = null,Object? node = freezed,Object? value = freezed,Object? action = freezed,Object? args = freezed,Object? seconds = freezed,Object? equals = freezed,Object? min = freezed,Object? max = freezed,Object? changes = null,Object? level = null,Object? after = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? modelWarn = freezed,Object? reason = freezed,Object? result = freezed,}) {
  return _then(AgentPlanStep(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AgentStepKind,node: freezed == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as Value?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: freezed == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as Value?,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,equals: freezed == equals ? _self.equals : equals // ignore: cast_nullable_to_non_nullable
as Value?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as double?,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as double?,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as bool,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as List<int>,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as AgentStepCheck,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,modelWarn: freezed == modelWarn ? _self.modelWarn : modelWarn // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as AgentStepResult?,
  ));
}
/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStepResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $AgentStepResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentPlanStep].
extension AgentPlanStepPatterns on AgentPlanStep {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentPlanStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentPlanStep() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentPlanStep value)  $default,){
final _that = this;
switch (_that) {
case _AgentPlanStep():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentPlanStep value)?  $default,){
final _that = this;
switch (_that) {
case _AgentPlanStep() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int n,  AgentStepKind kind,  String? node,  Value? value,  String? action,  Value? args,  double? seconds,  Value? equals,  double? min,  double? max,  bool changes,  Perm level,  List<int> after,  bool approval,  AgentStepCheck check,  String? warn,  String? modelWarn,  String? reason,  AgentStepResult? result)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentPlanStep() when $default != null:
return $default(_that.n,_that.kind,_that.node,_that.value,_that.action,_that.args,_that.seconds,_that.equals,_that.min,_that.max,_that.changes,_that.level,_that.after,_that.approval,_that.check,_that.warn,_that.modelWarn,_that.reason,_that.result);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int n,  AgentStepKind kind,  String? node,  Value? value,  String? action,  Value? args,  double? seconds,  Value? equals,  double? min,  double? max,  bool changes,  Perm level,  List<int> after,  bool approval,  AgentStepCheck check,  String? warn,  String? modelWarn,  String? reason,  AgentStepResult? result)  $default,) {final _that = this;
switch (_that) {
case _AgentPlanStep():
return $default(_that.n,_that.kind,_that.node,_that.value,_that.action,_that.args,_that.seconds,_that.equals,_that.min,_that.max,_that.changes,_that.level,_that.after,_that.approval,_that.check,_that.warn,_that.modelWarn,_that.reason,_that.result);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int n,  AgentStepKind kind,  String? node,  Value? value,  String? action,  Value? args,  double? seconds,  Value? equals,  double? min,  double? max,  bool changes,  Perm level,  List<int> after,  bool approval,  AgentStepCheck check,  String? warn,  String? modelWarn,  String? reason,  AgentStepResult? result)?  $default,) {final _that = this;
switch (_that) {
case _AgentPlanStep() when $default != null:
return $default(_that.n,_that.kind,_that.node,_that.value,_that.action,_that.args,_that.seconds,_that.equals,_that.min,_that.max,_that.changes,_that.level,_that.after,_that.approval,_that.check,_that.warn,_that.modelWarn,_that.reason,_that.result);case _:
  return null;

}
}

}

/// @nodoc


class _AgentPlanStep implements AgentPlanStep {
  const _AgentPlanStep({required this.n, required this.kind, this.node, this.value, this.action, this.args, this.seconds, this.equals, this.min, this.max, this.changes = false, required this.level,  List<int> after = const <int>[], this.approval = false, this.check = AgentStepCheck.now, this.warn, this.modelWarn, this.reason, this.result}): _after = after;
  

/// The step's number, from 1.
@override final  int n;
@override final  AgentStepKind kind;
/// The full node key; null for [AgentStepKind.sleep].
@override final  String? node;
/// `set`: the value to write.
@override final  Value? value;
/// `invoke`: the action and its arguments.
@override final  String? action;
@override final  Value? args;
/// `wait`/`expect`: how long to wait; `sleep`: how long to sleep (s).
@override final  double? seconds;
/// `expect`: the value to see, or the range, or any change.
@override final  Value? equals;
@override final  double? min;
@override final  double? max;
@override@JsonKey() final  bool changes;
/// The level the step needs.
@override final  Perm level;
/// The steps (`n`) this one runs after.
 final  List<int> _after;
/// The steps (`n`) this one runs after.
@override@JsonKey() List<int> get after {
  if (_after is EqualUnmodifiableListView) return _after;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_after);
}

/// It needs a person's approval (the bar of now).
@override@JsonKey() final  bool approval;
@override@JsonKey() final  AgentStepCheck check;
/// The link's own finding about the step.
@override final  String? warn;
/// The model's words about a risk.
@override final  String? modelWarn;
@override final  String? reason;
@override final  AgentStepResult? result;

/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentPlanStepCopyWith<_AgentPlanStep> get copyWith => __$AgentPlanStepCopyWithImpl<_AgentPlanStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentPlanStep&&(identical(other.n, n) || other.n == n)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.node, node) || other.node == node)&&(identical(other.value, value) || other.value == value)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args)&&(identical(other.seconds, seconds) || other.seconds == seconds)&&(identical(other.equals, equals) || other.equals == equals)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&(identical(other.changes, changes) || other.changes == changes)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other.after, _after)&&(identical(other.approval, approval) || other.approval == approval)&&(identical(other.check, check) || other.check == check)&&(identical(other.warn, warn) || other.warn == warn)&&(identical(other.modelWarn, modelWarn) || other.modelWarn == modelWarn)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,n,kind,node,value,action,args,seconds,equals,min,max,changes,level,const DeepCollectionEquality().hash(_after),approval,check,warn,modelWarn,reason,result]);
}

@override
String toString() {
    return 'AgentPlanStep(n: $n, kind: $kind, node: $node, value: $value, action: $action, args: $args, seconds: $seconds, equals: $equals, min: $min, max: $max, changes: $changes, level: $level, after: $after, approval: $approval, check: $check, warn: $warn, modelWarn: $modelWarn, reason: $reason, result: $result)';
}


}

/// @nodoc
abstract mixin class _$AgentPlanStepCopyWith<$Res> implements $AgentPlanStepCopyWith<$Res> {
  factory _$AgentPlanStepCopyWith(_AgentPlanStep value, $Res Function(_AgentPlanStep) _then) = __$AgentPlanStepCopyWithImpl;
@override @useResult
$Res call({
 int n, AgentStepKind kind, String? node, Value? value, String? action, Value? args, double? seconds, Value? equals, double? min, double? max, bool changes, Perm level, List<int> after, bool approval, AgentStepCheck check, String? warn, String? modelWarn, String? reason, AgentStepResult? result
});


@override $AgentStepResultCopyWith<$Res>? get result;

}
/// @nodoc
class __$AgentPlanStepCopyWithImpl<$Res>
    implements _$AgentPlanStepCopyWith<$Res> {
  __$AgentPlanStepCopyWithImpl(this._self, this._then);

  final _AgentPlanStep _self;
  final $Res Function(_AgentPlanStep) _then;

/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? n = null,Object? kind = null,Object? node = freezed,Object? value = freezed,Object? action = freezed,Object? args = freezed,Object? seconds = freezed,Object? equals = freezed,Object? min = freezed,Object? max = freezed,Object? changes = null,Object? level = null,Object? after = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? modelWarn = freezed,Object? reason = freezed,Object? result = freezed,}) {
  return _then(_AgentPlanStep(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AgentStepKind,node: freezed == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as Value?,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: freezed == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as Value?,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,equals: freezed == equals ? _self.equals : equals // ignore: cast_nullable_to_non_nullable
as Value?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as double?,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as double?,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as bool,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,after: null == after ? _self._after : after // ignore: cast_nullable_to_non_nullable
as List<int>,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as AgentStepCheck,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,modelWarn: freezed == modelWarn ? _self.modelWarn : modelWarn // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as AgentStepResult?,
  ));
}

/// Create a copy of AgentPlanStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStepResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $AgentStepResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc
mixin _$AgentLastStep {

 int get n; bool get ok; AgentStepStatus get result;
/// Create a copy of AgentLastStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentLastStepCopyWith<AgentLastStep> get copyWith => _$AgentLastStepCopyWithImpl<AgentLastStep>(this as AgentLastStep, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentLastStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentLastStep&&(identical(other.n, _this.n) || other.n == _this.n)&&(identical(other.ok, _this.ok) || other.ok == _this.ok)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as AgentLastStep;
  return Object.hash(runtimeType,_this.n,_this.ok,_this.result);
}

@override
String toString() {
  final _this = this as AgentLastStep;
  return 'AgentLastStep(n: ${_this.n}, ok: ${_this.ok}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $AgentLastStepCopyWith<$Res>  {
  factory $AgentLastStepCopyWith(AgentLastStep value, $Res Function(AgentLastStep) _then) = _$AgentLastStepCopyWithImpl;
@useResult
$Res call({
 int n, bool ok, AgentStepStatus result
});




}
/// @nodoc
class _$AgentLastStepCopyWithImpl<$Res>
    implements $AgentLastStepCopyWith<$Res> {
  _$AgentLastStepCopyWithImpl(this._self, this._then);

  final AgentLastStep _self;
  final $Res Function(AgentLastStep) _then;

/// Create a copy of AgentLastStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? n = null,Object? ok = null,Object? result = null,}) {
  return _then(AgentLastStep(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as AgentStepStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentLastStep].
extension AgentLastStepPatterns on AgentLastStep {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentLastStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentLastStep() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentLastStep value)  $default,){
final _that = this;
switch (_that) {
case _AgentLastStep():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentLastStep value)?  $default,){
final _that = this;
switch (_that) {
case _AgentLastStep() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int n,  bool ok,  AgentStepStatus result)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentLastStep() when $default != null:
return $default(_that.n,_that.ok,_that.result);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int n,  bool ok,  AgentStepStatus result)  $default,) {final _that = this;
switch (_that) {
case _AgentLastStep():
return $default(_that.n,_that.ok,_that.result);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int n,  bool ok,  AgentStepStatus result)?  $default,) {final _that = this;
switch (_that) {
case _AgentLastStep() when $default != null:
return $default(_that.n,_that.ok,_that.result);case _:
  return null;

}
}

}

/// @nodoc


class _AgentLastStep implements AgentLastStep {
  const _AgentLastStep({required this.n, required this.ok, required this.result});
  

@override final  int n;
@override final  bool ok;
@override final  AgentStepStatus result;

/// Create a copy of AgentLastStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentLastStepCopyWith<_AgentLastStep> get copyWith => __$AgentLastStepCopyWithImpl<_AgentLastStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentLastStep&&(identical(other.n, n) || other.n == n)&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,n,ok,result);
}

@override
String toString() {
    return 'AgentLastStep(n: $n, ok: $ok, result: $result)';
}


}

/// @nodoc
abstract mixin class _$AgentLastStepCopyWith<$Res> implements $AgentLastStepCopyWith<$Res> {
  factory _$AgentLastStepCopyWith(_AgentLastStep value, $Res Function(_AgentLastStep) _then) = __$AgentLastStepCopyWithImpl;
@override @useResult
$Res call({
 int n, bool ok, AgentStepStatus result
});




}
/// @nodoc
class __$AgentLastStepCopyWithImpl<$Res>
    implements _$AgentLastStepCopyWith<$Res> {
  __$AgentLastStepCopyWithImpl(this._self, this._then);

  final _AgentLastStep _self;
  final $Res Function(_AgentLastStep) _then;

/// Create a copy of AgentLastStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? n = null,Object? ok = null,Object? result = null,}) {
  return _then(_AgentLastStep(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as AgentStepStatus,
  ));
}


}

/// @nodoc
mixin _$AgentTaskValue {

 AgentTaskState get state;/// Steps run so far, of [of].
 int get step; int get of; AgentLastStep? get last;/// How many suggestions and findings the record holds.
 int get suggestions; int get findings;/// The model reads why the run stopped.
 bool get reviewing;/// The follow-up task that took this one's place.
 String? get replacedBy;
/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentTaskValueCopyWith<AgentTaskValue> get copyWith => _$AgentTaskValueCopyWithImpl<AgentTaskValue>(this as AgentTaskValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentTaskValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentTaskValue&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.of, _this.of) || other.of == _this.of)&&(identical(other.last, _this.last) || other.last == _this.last)&&(identical(other.suggestions, _this.suggestions) || other.suggestions == _this.suggestions)&&(identical(other.findings, _this.findings) || other.findings == _this.findings)&&(identical(other.reviewing, _this.reviewing) || other.reviewing == _this.reviewing)&&(identical(other.replacedBy, _this.replacedBy) || other.replacedBy == _this.replacedBy));
}


@override
int get hashCode {
  final _this = this as AgentTaskValue;
  return Object.hash(runtimeType,_this.state,_this.step,_this.of,_this.last,_this.suggestions,_this.findings,_this.reviewing,_this.replacedBy);
}

@override
String toString() {
  final _this = this as AgentTaskValue;
  return 'AgentTaskValue(state: ${_this.state}, step: ${_this.step}, of: ${_this.of}, last: ${_this.last}, suggestions: ${_this.suggestions}, findings: ${_this.findings}, reviewing: ${_this.reviewing}, replacedBy: ${_this.replacedBy})';
}


}

/// @nodoc
abstract mixin class $AgentTaskValueCopyWith<$Res>  {
  factory $AgentTaskValueCopyWith(AgentTaskValue value, $Res Function(AgentTaskValue) _then) = _$AgentTaskValueCopyWithImpl;
@useResult
$Res call({
 AgentTaskState state, int step, int of, AgentLastStep? last, int suggestions, int findings, bool reviewing, String? replacedBy
});


$AgentLastStepCopyWith<$Res>? get last;

}
/// @nodoc
class _$AgentTaskValueCopyWithImpl<$Res>
    implements $AgentTaskValueCopyWith<$Res> {
  _$AgentTaskValueCopyWithImpl(this._self, this._then);

  final AgentTaskValue _self;
  final $Res Function(AgentTaskValue) _then;

/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? step = null,Object? of = null,Object? last = freezed,Object? suggestions = null,Object? findings = null,Object? reviewing = null,Object? replacedBy = freezed,}) {
  return _then(AgentTaskValue(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentTaskState,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,of: null == of ? _self.of : of // ignore: cast_nullable_to_non_nullable
as int,last: freezed == last ? _self.last : last // ignore: cast_nullable_to_non_nullable
as AgentLastStep?,suggestions: null == suggestions ? _self.suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as int,findings: null == findings ? _self.findings : findings // ignore: cast_nullable_to_non_nullable
as int,reviewing: null == reviewing ? _self.reviewing : reviewing // ignore: cast_nullable_to_non_nullable
as bool,replacedBy: freezed == replacedBy ? _self.replacedBy : replacedBy // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentLastStepCopyWith<$Res>? get last {
    if (_self.last == null) {
    return null;
  }

  return $AgentLastStepCopyWith<$Res>(_self.last!, (value) {
    return _then(_self.copyWith(last: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentTaskValue].
extension AgentTaskValuePatterns on AgentTaskValue {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentTaskValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentTaskValue() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentTaskValue value)  $default,){
final _that = this;
switch (_that) {
case _AgentTaskValue():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentTaskValue value)?  $default,){
final _that = this;
switch (_that) {
case _AgentTaskValue() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AgentTaskState state,  int step,  int of,  AgentLastStep? last,  int suggestions,  int findings,  bool reviewing,  String? replacedBy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentTaskValue() when $default != null:
return $default(_that.state,_that.step,_that.of,_that.last,_that.suggestions,_that.findings,_that.reviewing,_that.replacedBy);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AgentTaskState state,  int step,  int of,  AgentLastStep? last,  int suggestions,  int findings,  bool reviewing,  String? replacedBy)  $default,) {final _that = this;
switch (_that) {
case _AgentTaskValue():
return $default(_that.state,_that.step,_that.of,_that.last,_that.suggestions,_that.findings,_that.reviewing,_that.replacedBy);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AgentTaskState state,  int step,  int of,  AgentLastStep? last,  int suggestions,  int findings,  bool reviewing,  String? replacedBy)?  $default,) {final _that = this;
switch (_that) {
case _AgentTaskValue() when $default != null:
return $default(_that.state,_that.step,_that.of,_that.last,_that.suggestions,_that.findings,_that.reviewing,_that.replacedBy);case _:
  return null;

}
}

}

/// @nodoc


class _AgentTaskValue implements AgentTaskValue {
  const _AgentTaskValue({required this.state, required this.step, required this.of, this.last, this.suggestions = 0, this.findings = 0, this.reviewing = false, this.replacedBy});
  

@override final  AgentTaskState state;
/// Steps run so far, of [of].
@override final  int step;
@override final  int of;
@override final  AgentLastStep? last;
/// How many suggestions and findings the record holds.
@override@JsonKey() final  int suggestions;
@override@JsonKey() final  int findings;
/// The model reads why the run stopped.
@override@JsonKey() final  bool reviewing;
/// The follow-up task that took this one's place.
@override final  String? replacedBy;

/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentTaskValueCopyWith<_AgentTaskValue> get copyWith => __$AgentTaskValueCopyWithImpl<_AgentTaskValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentTaskValue&&(identical(other.state, state) || other.state == state)&&(identical(other.step, step) || other.step == step)&&(identical(other.of, of) || other.of == of)&&(identical(other.last, last) || other.last == last)&&(identical(other.suggestions, suggestions) || other.suggestions == suggestions)&&(identical(other.findings, findings) || other.findings == findings)&&(identical(other.reviewing, reviewing) || other.reviewing == reviewing)&&(identical(other.replacedBy, replacedBy) || other.replacedBy == replacedBy));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,step,of,last,suggestions,findings,reviewing,replacedBy);
}

@override
String toString() {
    return 'AgentTaskValue(state: $state, step: $step, of: $of, last: $last, suggestions: $suggestions, findings: $findings, reviewing: $reviewing, replacedBy: $replacedBy)';
}


}

/// @nodoc
abstract mixin class _$AgentTaskValueCopyWith<$Res> implements $AgentTaskValueCopyWith<$Res> {
  factory _$AgentTaskValueCopyWith(_AgentTaskValue value, $Res Function(_AgentTaskValue) _then) = __$AgentTaskValueCopyWithImpl;
@override @useResult
$Res call({
 AgentTaskState state, int step, int of, AgentLastStep? last, int suggestions, int findings, bool reviewing, String? replacedBy
});


@override $AgentLastStepCopyWith<$Res>? get last;

}
/// @nodoc
class __$AgentTaskValueCopyWithImpl<$Res>
    implements _$AgentTaskValueCopyWith<$Res> {
  __$AgentTaskValueCopyWithImpl(this._self, this._then);

  final _AgentTaskValue _self;
  final $Res Function(_AgentTaskValue) _then;

/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? step = null,Object? of = null,Object? last = freezed,Object? suggestions = null,Object? findings = null,Object? reviewing = null,Object? replacedBy = freezed,}) {
  return _then(_AgentTaskValue(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentTaskState,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,of: null == of ? _self.of : of // ignore: cast_nullable_to_non_nullable
as int,last: freezed == last ? _self.last : last // ignore: cast_nullable_to_non_nullable
as AgentLastStep?,suggestions: null == suggestions ? _self.suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as int,findings: null == findings ? _self.findings : findings // ignore: cast_nullable_to_non_nullable
as int,reviewing: null == reviewing ? _self.reviewing : reviewing // ignore: cast_nullable_to_non_nullable
as bool,replacedBy: freezed == replacedBy ? _self.replacedBy : replacedBy // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AgentTaskValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentLastStepCopyWith<$Res>? get last {
    if (_self.last == null) {
    return null;
  }

  return $AgentLastStepCopyWith<$Res>(_self.last!, (value) {
    return _then(_self.copyWith(last: value));
  });
}
}

/// @nodoc
mixin _$AgentTaskRecord {

 AgentTaskState get state;/// The subject who asked.
 String get owner;/// What the person asked.
 String get ask; List<AgentPlanStep> get plan;/// The hash of the plan the link holds (`plan_hash`).
 String get planHash;/// [planHash] of the plan in this record, made here: what an approval
/// of the plan as shown sends (`approve {plan}`).
 String get shownPlanHash; List<AgentQuestion> get questions; List<TaskSuggestion> get suggestions; List<TaskFinding> get findings;/// The findings not noted, by why (reasons this client does not know
/// are left out).
 Map<AgentFindingRefusal, int> get findingsRefused;/// The task this one follows (a retry, an undo, another plan).
 String? get parent;/// The follow-up task that took this one's place: its plan is shown as
/// replaced and cannot be approved.
 String? get replacedBy;/// Node keys the person attached.
 List<String> get context;/// Steps run so far.
 int get step; List<String> get log; String? get error;/// What the model found after the run stopped.
 String? get review;/// The model reads why the run stopped; its ways out come as
/// suggestions when it ends.
 bool get reviewing;/// LLM tokens the task used.
 int get tokens;
/// Create a copy of AgentTaskRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentTaskRecordCopyWith<AgentTaskRecord> get copyWith => _$AgentTaskRecordCopyWithImpl<AgentTaskRecord>(this as AgentTaskRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentTaskRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentTaskRecord&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.ask, _this.ask) || other.ask == _this.ask)&&const DeepCollectionEquality().equals(other.plan, _this.plan)&&(identical(other.planHash, _this.planHash) || other.planHash == _this.planHash)&&(identical(other.shownPlanHash, _this.shownPlanHash) || other.shownPlanHash == _this.shownPlanHash)&&const DeepCollectionEquality().equals(other.questions, _this.questions)&&const DeepCollectionEquality().equals(other.suggestions, _this.suggestions)&&const DeepCollectionEquality().equals(other.findings, _this.findings)&&const DeepCollectionEquality().equals(other.findingsRefused, _this.findingsRefused)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&(identical(other.replacedBy, _this.replacedBy) || other.replacedBy == _this.replacedBy)&&const DeepCollectionEquality().equals(other.context, _this.context)&&(identical(other.step, _this.step) || other.step == _this.step)&&const DeepCollectionEquality().equals(other.log, _this.log)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.review, _this.review) || other.review == _this.review)&&(identical(other.reviewing, _this.reviewing) || other.reviewing == _this.reviewing)&&(identical(other.tokens, _this.tokens) || other.tokens == _this.tokens));
}


@override
int get hashCode {
  final _this = this as AgentTaskRecord;
  return Object.hashAll([runtimeType,_this.state,_this.owner,_this.ask,const DeepCollectionEquality().hash(_this.plan),_this.planHash,_this.shownPlanHash,const DeepCollectionEquality().hash(_this.questions),const DeepCollectionEquality().hash(_this.suggestions),const DeepCollectionEquality().hash(_this.findings),const DeepCollectionEquality().hash(_this.findingsRefused),_this.parent,_this.replacedBy,const DeepCollectionEquality().hash(_this.context),_this.step,const DeepCollectionEquality().hash(_this.log),_this.error,_this.review,_this.reviewing,_this.tokens]);
}

@override
String toString() {
  final _this = this as AgentTaskRecord;
  return 'AgentTaskRecord(state: ${_this.state}, owner: ${_this.owner}, ask: ${_this.ask}, plan: ${_this.plan}, planHash: ${_this.planHash}, shownPlanHash: ${_this.shownPlanHash}, questions: ${_this.questions}, suggestions: ${_this.suggestions}, findings: ${_this.findings}, findingsRefused: ${_this.findingsRefused}, parent: ${_this.parent}, replacedBy: ${_this.replacedBy}, context: ${_this.context}, step: ${_this.step}, log: ${_this.log}, error: ${_this.error}, review: ${_this.review}, reviewing: ${_this.reviewing}, tokens: ${_this.tokens})';
}


}

/// @nodoc
abstract mixin class $AgentTaskRecordCopyWith<$Res>  {
  factory $AgentTaskRecordCopyWith(AgentTaskRecord value, $Res Function(AgentTaskRecord) _then) = _$AgentTaskRecordCopyWithImpl;
@useResult
$Res call({
 AgentTaskState state, String owner, String ask, List<AgentPlanStep> plan, String planHash, String shownPlanHash, List<AgentQuestion> questions, List<TaskSuggestion> suggestions, List<TaskFinding> findings, Map<AgentFindingRefusal, int> findingsRefused, String? parent, String? replacedBy, List<String> context, int step, List<String> log, String? error, String? review, bool reviewing, int tokens
});




}
/// @nodoc
class _$AgentTaskRecordCopyWithImpl<$Res>
    implements $AgentTaskRecordCopyWith<$Res> {
  _$AgentTaskRecordCopyWithImpl(this._self, this._then);

  final AgentTaskRecord _self;
  final $Res Function(AgentTaskRecord) _then;

/// Create a copy of AgentTaskRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? planHash = null,Object? shownPlanHash = null,Object? questions = null,Object? suggestions = null,Object? findings = null,Object? findingsRefused = null,Object? parent = freezed,Object? replacedBy = freezed,Object? context = null,Object? step = null,Object? log = null,Object? error = freezed,Object? review = freezed,Object? reviewing = null,Object? tokens = null,}) {
  return _then(AgentTaskRecord(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentTaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as List<AgentPlanStep>,planHash: null == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as String,shownPlanHash: null == shownPlanHash ? _self.shownPlanHash : shownPlanHash // ignore: cast_nullable_to_non_nullable
as String,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<AgentQuestion>,suggestions: null == suggestions ? _self.suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as List<TaskSuggestion>,findings: null == findings ? _self.findings : findings // ignore: cast_nullable_to_non_nullable
as List<TaskFinding>,findingsRefused: null == findingsRefused ? _self.findingsRefused : findingsRefused // ignore: cast_nullable_to_non_nullable
as Map<AgentFindingRefusal, int>,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,replacedBy: freezed == replacedBy ? _self.replacedBy : replacedBy // ignore: cast_nullable_to_non_nullable
as String?,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as List<String>,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as List<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,review: freezed == review ? _self.review : review // ignore: cast_nullable_to_non_nullable
as String?,reviewing: null == reviewing ? _self.reviewing : reviewing // ignore: cast_nullable_to_non_nullable
as bool,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentTaskRecord].
extension AgentTaskRecordPatterns on AgentTaskRecord {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentTaskRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentTaskRecord() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentTaskRecord value)  $default,){
final _that = this;
switch (_that) {
case _AgentTaskRecord():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentTaskRecord value)?  $default,){
final _that = this;
switch (_that) {
case _AgentTaskRecord() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AgentTaskState state,  String owner,  String ask,  List<AgentPlanStep> plan,  String planHash,  String shownPlanHash,  List<AgentQuestion> questions,  List<TaskSuggestion> suggestions,  List<TaskFinding> findings,  Map<AgentFindingRefusal, int> findingsRefused,  String? parent,  String? replacedBy,  List<String> context,  int step,  List<String> log,  String? error,  String? review,  bool reviewing,  int tokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentTaskRecord() when $default != null:
return $default(_that.state,_that.owner,_that.ask,_that.plan,_that.planHash,_that.shownPlanHash,_that.questions,_that.suggestions,_that.findings,_that.findingsRefused,_that.parent,_that.replacedBy,_that.context,_that.step,_that.log,_that.error,_that.review,_that.reviewing,_that.tokens);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AgentTaskState state,  String owner,  String ask,  List<AgentPlanStep> plan,  String planHash,  String shownPlanHash,  List<AgentQuestion> questions,  List<TaskSuggestion> suggestions,  List<TaskFinding> findings,  Map<AgentFindingRefusal, int> findingsRefused,  String? parent,  String? replacedBy,  List<String> context,  int step,  List<String> log,  String? error,  String? review,  bool reviewing,  int tokens)  $default,) {final _that = this;
switch (_that) {
case _AgentTaskRecord():
return $default(_that.state,_that.owner,_that.ask,_that.plan,_that.planHash,_that.shownPlanHash,_that.questions,_that.suggestions,_that.findings,_that.findingsRefused,_that.parent,_that.replacedBy,_that.context,_that.step,_that.log,_that.error,_that.review,_that.reviewing,_that.tokens);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AgentTaskState state,  String owner,  String ask,  List<AgentPlanStep> plan,  String planHash,  String shownPlanHash,  List<AgentQuestion> questions,  List<TaskSuggestion> suggestions,  List<TaskFinding> findings,  Map<AgentFindingRefusal, int> findingsRefused,  String? parent,  String? replacedBy,  List<String> context,  int step,  List<String> log,  String? error,  String? review,  bool reviewing,  int tokens)?  $default,) {final _that = this;
switch (_that) {
case _AgentTaskRecord() when $default != null:
return $default(_that.state,_that.owner,_that.ask,_that.plan,_that.planHash,_that.shownPlanHash,_that.questions,_that.suggestions,_that.findings,_that.findingsRefused,_that.parent,_that.replacedBy,_that.context,_that.step,_that.log,_that.error,_that.review,_that.reviewing,_that.tokens);case _:
  return null;

}
}

}

/// @nodoc


class _AgentTaskRecord implements AgentTaskRecord {
  const _AgentTaskRecord({required this.state, required this.owner, required this.ask, required  List<AgentPlanStep> plan, required this.planHash, required this.shownPlanHash,  List<AgentQuestion> questions = const <AgentQuestion>[],  List<TaskSuggestion> suggestions = const <TaskSuggestion>[],  List<TaskFinding> findings = const <TaskFinding>[],  Map<AgentFindingRefusal, int> findingsRefused = const <AgentFindingRefusal, int>{}, this.parent, this.replacedBy,  List<String> context = const <String>[], required this.step, required  List<String> log, this.error, this.review, this.reviewing = false, required this.tokens}): _plan = plan,_questions = questions,_suggestions = suggestions,_findings = findings,_findingsRefused = findingsRefused,_context = context,_log = log;
  

@override final  AgentTaskState state;
/// The subject who asked.
@override final  String owner;
/// What the person asked.
@override final  String ask;
 final  List<AgentPlanStep> _plan;
@override List<AgentPlanStep> get plan {
  if (_plan is EqualUnmodifiableListView) return _plan;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_plan);
}

/// The hash of the plan the link holds (`plan_hash`).
@override final  String planHash;
/// [planHash] of the plan in this record, made here: what an approval
/// of the plan as shown sends (`approve {plan}`).
@override final  String shownPlanHash;
 final  List<AgentQuestion> _questions;
@override@JsonKey() List<AgentQuestion> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}

 final  List<TaskSuggestion> _suggestions;
@override@JsonKey() List<TaskSuggestion> get suggestions {
  if (_suggestions is EqualUnmodifiableListView) return _suggestions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_suggestions);
}

 final  List<TaskFinding> _findings;
@override@JsonKey() List<TaskFinding> get findings {
  if (_findings is EqualUnmodifiableListView) return _findings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_findings);
}

/// The findings not noted, by why (reasons this client does not know
/// are left out).
 final  Map<AgentFindingRefusal, int> _findingsRefused;
/// The findings not noted, by why (reasons this client does not know
/// are left out).
@override@JsonKey() Map<AgentFindingRefusal, int> get findingsRefused {
  if (_findingsRefused is EqualUnmodifiableMapView) return _findingsRefused;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_findingsRefused);
}

/// The task this one follows (a retry, an undo, another plan).
@override final  String? parent;
/// The follow-up task that took this one's place: its plan is shown as
/// replaced and cannot be approved.
@override final  String? replacedBy;
/// Node keys the person attached.
 final  List<String> _context;
/// Node keys the person attached.
@override@JsonKey() List<String> get context {
  if (_context is EqualUnmodifiableListView) return _context;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_context);
}

/// Steps run so far.
@override final  int step;
 final  List<String> _log;
@override List<String> get log {
  if (_log is EqualUnmodifiableListView) return _log;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_log);
}

@override final  String? error;
/// What the model found after the run stopped.
@override final  String? review;
/// The model reads why the run stopped; its ways out come as
/// suggestions when it ends.
@override@JsonKey() final  bool reviewing;
/// LLM tokens the task used.
@override final  int tokens;

/// Create a copy of AgentTaskRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentTaskRecordCopyWith<_AgentTaskRecord> get copyWith => __$AgentTaskRecordCopyWithImpl<_AgentTaskRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentTaskRecord&&(identical(other.state, state) || other.state == state)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.ask, ask) || other.ask == ask)&&const DeepCollectionEquality().equals(other.plan, _plan)&&(identical(other.planHash, planHash) || other.planHash == planHash)&&(identical(other.shownPlanHash, shownPlanHash) || other.shownPlanHash == shownPlanHash)&&const DeepCollectionEquality().equals(other.questions, _questions)&&const DeepCollectionEquality().equals(other.suggestions, _suggestions)&&const DeepCollectionEquality().equals(other.findings, _findings)&&const DeepCollectionEquality().equals(other.findingsRefused, _findingsRefused)&&(identical(other.parent, parent) || other.parent == parent)&&(identical(other.replacedBy, replacedBy) || other.replacedBy == replacedBy)&&const DeepCollectionEquality().equals(other.context, _context)&&(identical(other.step, step) || other.step == step)&&const DeepCollectionEquality().equals(other.log, _log)&&(identical(other.error, error) || other.error == error)&&(identical(other.review, review) || other.review == review)&&(identical(other.reviewing, reviewing) || other.reviewing == reviewing)&&(identical(other.tokens, tokens) || other.tokens == tokens));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,state,owner,ask,const DeepCollectionEquality().hash(_plan),planHash,shownPlanHash,const DeepCollectionEquality().hash(_questions),const DeepCollectionEquality().hash(_suggestions),const DeepCollectionEquality().hash(_findings),const DeepCollectionEquality().hash(_findingsRefused),parent,replacedBy,const DeepCollectionEquality().hash(_context),step,const DeepCollectionEquality().hash(_log),error,review,reviewing,tokens]);
}

@override
String toString() {
    return 'AgentTaskRecord(state: $state, owner: $owner, ask: $ask, plan: $plan, planHash: $planHash, shownPlanHash: $shownPlanHash, questions: $questions, suggestions: $suggestions, findings: $findings, findingsRefused: $findingsRefused, parent: $parent, replacedBy: $replacedBy, context: $context, step: $step, log: $log, error: $error, review: $review, reviewing: $reviewing, tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class _$AgentTaskRecordCopyWith<$Res> implements $AgentTaskRecordCopyWith<$Res> {
  factory _$AgentTaskRecordCopyWith(_AgentTaskRecord value, $Res Function(_AgentTaskRecord) _then) = __$AgentTaskRecordCopyWithImpl;
@override @useResult
$Res call({
 AgentTaskState state, String owner, String ask, List<AgentPlanStep> plan, String planHash, String shownPlanHash, List<AgentQuestion> questions, List<TaskSuggestion> suggestions, List<TaskFinding> findings, Map<AgentFindingRefusal, int> findingsRefused, String? parent, String? replacedBy, List<String> context, int step, List<String> log, String? error, String? review, bool reviewing, int tokens
});




}
/// @nodoc
class __$AgentTaskRecordCopyWithImpl<$Res>
    implements _$AgentTaskRecordCopyWith<$Res> {
  __$AgentTaskRecordCopyWithImpl(this._self, this._then);

  final _AgentTaskRecord _self;
  final $Res Function(_AgentTaskRecord) _then;

/// Create a copy of AgentTaskRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? planHash = null,Object? shownPlanHash = null,Object? questions = null,Object? suggestions = null,Object? findings = null,Object? findingsRefused = null,Object? parent = freezed,Object? replacedBy = freezed,Object? context = null,Object? step = null,Object? log = null,Object? error = freezed,Object? review = freezed,Object? reviewing = null,Object? tokens = null,}) {
  return _then(_AgentTaskRecord(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentTaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self._plan : plan // ignore: cast_nullable_to_non_nullable
as List<AgentPlanStep>,planHash: null == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as String,shownPlanHash: null == shownPlanHash ? _self.shownPlanHash : shownPlanHash // ignore: cast_nullable_to_non_nullable
as String,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<AgentQuestion>,suggestions: null == suggestions ? _self._suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as List<TaskSuggestion>,findings: null == findings ? _self._findings : findings // ignore: cast_nullable_to_non_nullable
as List<TaskFinding>,findingsRefused: null == findingsRefused ? _self._findingsRefused : findingsRefused // ignore: cast_nullable_to_non_nullable
as Map<AgentFindingRefusal, int>,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,replacedBy: freezed == replacedBy ? _self.replacedBy : replacedBy // ignore: cast_nullable_to_non_nullable
as String?,context: null == context ? _self._context : context // ignore: cast_nullable_to_non_nullable
as List<String>,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,log: null == log ? _self._log : log // ignore: cast_nullable_to_non_nullable
as List<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,review: freezed == review ? _self.review : review // ignore: cast_nullable_to_non_nullable
as String?,reviewing: null == reviewing ? _self.reviewing : reviewing // ignore: cast_nullable_to_non_nullable
as bool,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AgentReply {

 String get task;
/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentReplyCopyWith<AgentReply> get copyWith => _$AgentReplyCopyWithImpl<AgentReply>(this as AgentReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentReply&&(identical(other.task, _this.task) || other.task == _this.task));
}


@override
int get hashCode {
  final _this = this as AgentReply;
  return Object.hash(runtimeType,_this.task);
}

@override
String toString() {
  final _this = this as AgentReply;
  return 'AgentReply(task: ${_this.task})';
}


}

/// @nodoc
abstract mixin class $AgentReplyCopyWith<$Res>  {
  factory $AgentReplyCopyWith(AgentReply value, $Res Function(AgentReply) _then) = _$AgentReplyCopyWithImpl;
@useResult
$Res call({
 String task
});




}
/// @nodoc
class _$AgentReplyCopyWithImpl<$Res>
    implements $AgentReplyCopyWith<$Res> {
  _$AgentReplyCopyWithImpl(this._self, this._then);

  final AgentReply _self;
  final $Res Function(AgentReply) _then;

/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? task = null,}) {
  return _then(_self.copyWith(
task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentReply].
extension AgentReplyPatterns on AgentReply {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentReplyState value)?  state,TResult Function( AgentReplyEvent value)?  event,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentReplyState() when state != null:
return state(_that);case AgentReplyEvent() when event != null:
return event(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentReplyState value)  state,required TResult Function( AgentReplyEvent value)  event,}){
final _that = this;
switch (_that) {
case AgentReplyState():
return state(_that);case AgentReplyEvent():
return event(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentReplyState value)?  state,TResult? Function( AgentReplyEvent value)?  event,}){
final _that = this;
switch (_that) {
case AgentReplyState() when state != null:
return state(_that);case AgentReplyEvent() when event != null:
return event(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String task,  AgentTaskState state)?  state,TResult Function( String task,  AgentEventKind kind,  String text)?  event,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentReplyState() when state != null:
return state(_that.task,_that.state);case AgentReplyEvent() when event != null:
return event(_that.task,_that.kind,_that.text);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String task,  AgentTaskState state)  state,required TResult Function( String task,  AgentEventKind kind,  String text)  event,}) {final _that = this;
switch (_that) {
case AgentReplyState():
return state(_that.task,_that.state);case AgentReplyEvent():
return event(_that.task,_that.kind,_that.text);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String task,  AgentTaskState state)?  state,TResult? Function( String task,  AgentEventKind kind,  String text)?  event,}) {final _that = this;
switch (_that) {
case AgentReplyState() when state != null:
return state(_that.task,_that.state);case AgentReplyEvent() when event != null:
return event(_that.task,_that.kind,_that.text);case _:
  return null;

}
}

}

/// @nodoc


class AgentReplyState extends AgentReply {
  const AgentReplyState({required this.task, required this.state}): super._();
  

@override final  String task;
 final  AgentTaskState state;

/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentReplyStateCopyWith<AgentReplyState> get copyWith => _$AgentReplyStateCopyWithImpl<AgentReplyState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentReplyState&&(identical(other.task, task) || other.task == task)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,task,state);
}

@override
String toString() {
    return 'AgentReply.state(task: $task, state: $state)';
}


}

/// @nodoc
abstract mixin class $AgentReplyStateCopyWith<$Res> implements $AgentReplyCopyWith<$Res> {
  factory $AgentReplyStateCopyWith(AgentReplyState value, $Res Function(AgentReplyState) _then) = _$AgentReplyStateCopyWithImpl;
@override @useResult
$Res call({
 String task, AgentTaskState state
});




}
/// @nodoc
class _$AgentReplyStateCopyWithImpl<$Res>
    implements $AgentReplyStateCopyWith<$Res> {
  _$AgentReplyStateCopyWithImpl(this._self, this._then);

  final AgentReplyState _self;
  final $Res Function(AgentReplyState) _then;

/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? task = null,Object? state = null,}) {
  return _then(AgentReplyState(
task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentTaskState,
  ));
}


}

/// @nodoc


class AgentReplyEvent extends AgentReply {
  const AgentReplyEvent({required this.task, required this.kind, required this.text}): super._();
  

@override final  String task;
 final  AgentEventKind kind;
 final  String text;

/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentReplyEventCopyWith<AgentReplyEvent> get copyWith => _$AgentReplyEventCopyWithImpl<AgentReplyEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentReplyEvent&&(identical(other.task, task) || other.task == task)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,task,kind,text);
}

@override
String toString() {
    return 'AgentReply.event(task: $task, kind: $kind, text: $text)';
}


}

/// @nodoc
abstract mixin class $AgentReplyEventCopyWith<$Res> implements $AgentReplyCopyWith<$Res> {
  factory $AgentReplyEventCopyWith(AgentReplyEvent value, $Res Function(AgentReplyEvent) _then) = _$AgentReplyEventCopyWithImpl;
@override @useResult
$Res call({
 String task, AgentEventKind kind, String text
});




}
/// @nodoc
class _$AgentReplyEventCopyWithImpl<$Res>
    implements $AgentReplyEventCopyWith<$Res> {
  _$AgentReplyEventCopyWithImpl(this._self, this._then);

  final AgentReplyEvent _self;
  final $Res Function(AgentReplyEvent) _then;

/// Create a copy of AgentReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? task = null,Object? kind = null,Object? text = null,}) {
  return _then(AgentReplyEvent(
task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AgentEventKind,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
