// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'studio_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StudioError {

 ErrorKind get kind;/// Given when the error is thrown; the Problems list finds it by this.
 int get id;/// What did not happen, with its object: `You can’t deploy
/// pump-control`. Composed from [kind], [call], [thing] and [site].
 String get title;/// The broker's words, as they came; empty when it sent none (a
/// timeout). For a fault in Studio: what happened, in Studio's words.
 String get message;/// The status of the refusal; null for Studio's own faults and for a
/// `{success: false}` answer.
 StatusCode? get status;/// The full key the call was made on.
 String? get key;/// The call: `deploy`, `set`, `subscribe`, `history`, `list`, …
 String? get call;/// The name of what the call was about (`pump-control`, `modbus
/// 0.4.2`), for the title; the last segment of [key] when null.
 String? get thing;/// The site the call went to.
 String? get site;/// When it failed, local time.
 DateTime? get at;/// Nobody was waiting for this call: a toast and a line in Problems, no
/// dialog.
 bool get quiet;/// The call changes something on the broker (`set`, `deploy`, an
/// action): a timeout then warns that it may have been applied.
 bool get write;/// Builds the action to dispatch again (*Try again*); null when the
/// call cannot be repeated as it was.
 Object Function()? get retry;/// Builds the load action of the screen it came from (*Refresh*).
 Object Function()? get reload;/// The parameter an `invalid_parameter` names, when the broker named
/// one.
 String? get field;/// Studio faults only.
 FaultReport? get report;/// Opened as a dialog (the drawer says so).
 bool get shown;/// A live stream of this site went down: its toast stays until the
/// stream is open again.
 String? get stream;/// The seconds *Try again* waits for (`busy`), when the broker gave a
/// hint; null for the default.
 int? get wait;
/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioErrorCopyWith<StudioError> get copyWith => _$StudioErrorCopyWithImpl<StudioError>(this as StudioError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioError&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.call, _this.call) || other.call == _this.call)&&(identical(other.thing, _this.thing) || other.thing == _this.thing)&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.at, _this.at) || other.at == _this.at)&&(identical(other.quiet, _this.quiet) || other.quiet == _this.quiet)&&(identical(other.write, _this.write) || other.write == _this.write)&&(identical(other.retry, _this.retry) || other.retry == _this.retry)&&(identical(other.reload, _this.reload) || other.reload == _this.reload)&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.report, _this.report) || other.report == _this.report)&&(identical(other.shown, _this.shown) || other.shown == _this.shown)&&(identical(other.stream, _this.stream) || other.stream == _this.stream)&&(identical(other.wait, _this.wait) || other.wait == _this.wait));
}


@override
int get hashCode {
  final _this = this as StudioError;
  return Object.hashAll([runtimeType,_this.kind,_this.id,_this.title,_this.message,_this.status,_this.key,_this.call,_this.thing,_this.site,_this.at,_this.quiet,_this.write,_this.retry,_this.reload,_this.field,_this.report,_this.shown,_this.stream,_this.wait]);
}

@override
String toString() {
  final _this = this as StudioError;
  return 'StudioError(kind: ${_this.kind}, id: ${_this.id}, title: ${_this.title}, message: ${_this.message}, status: ${_this.status}, key: ${_this.key}, call: ${_this.call}, thing: ${_this.thing}, site: ${_this.site}, at: ${_this.at}, quiet: ${_this.quiet}, write: ${_this.write}, retry: ${_this.retry}, reload: ${_this.reload}, field: ${_this.field}, report: ${_this.report}, shown: ${_this.shown}, stream: ${_this.stream}, wait: ${_this.wait})';
}


}

/// @nodoc
abstract mixin class $StudioErrorCopyWith<$Res>  {
  factory $StudioErrorCopyWith(StudioError value, $Res Function(StudioError) _then) = _$StudioErrorCopyWithImpl;
@useResult
$Res call({
 ErrorKind kind, int id, String title, String message, StatusCode? status, String? key, String? call, String? thing, String? site, DateTime? at, bool quiet, bool write, Object Function()? retry, Object Function()? reload, String? field, FaultReport? report, bool shown, String? stream, int? wait
});


$FaultReportCopyWith<$Res>? get report;

}
/// @nodoc
class _$StudioErrorCopyWithImpl<$Res>
    implements $StudioErrorCopyWith<$Res> {
  _$StudioErrorCopyWithImpl(this._self, this._then);

  final StudioError _self;
  final $Res Function(StudioError) _then;

/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? id = null,Object? title = null,Object? message = null,Object? status = freezed,Object? key = freezed,Object? call = freezed,Object? thing = freezed,Object? site = freezed,Object? at = freezed,Object? quiet = null,Object? write = null,Object? retry = freezed,Object? reload = freezed,Object? field = freezed,Object? report = freezed,Object? shown = null,Object? stream = freezed,Object? wait = freezed,}) {
  return _then(StudioError(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ErrorKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StatusCode?,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,call: freezed == call ? _self.call : call // ignore: cast_nullable_to_non_nullable
as String?,thing: freezed == thing ? _self.thing : thing // ignore: cast_nullable_to_non_nullable
as String?,site: freezed == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String?,at: freezed == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime?,quiet: null == quiet ? _self.quiet : quiet // ignore: cast_nullable_to_non_nullable
as bool,write: null == write ? _self.write : write // ignore: cast_nullable_to_non_nullable
as bool,retry: freezed == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as Object Function()?,reload: freezed == reload ? _self.reload : reload // ignore: cast_nullable_to_non_nullable
as Object Function()?,field: freezed == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String?,report: freezed == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as FaultReport?,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,stream: freezed == stream ? _self.stream : stream // ignore: cast_nullable_to_non_nullable
as String?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FaultReportCopyWith<$Res>? get report {
    if (_self.report == null) {
    return null;
  }

  return $FaultReportCopyWith<$Res>(_self.report!, (value) {
    return _then(_self.copyWith(report: value));
  });
}
}



/// @nodoc


class _StudioError extends StudioError {
  const _StudioError({required this.kind, this.id = 0, this.title = '', this.message = '', this.status, this.key, this.call, this.thing, this.site, this.at, this.quiet = false, this.write = false, this.retry, this.reload, this.field, this.report, this.shown = false, this.stream, this.wait}): super._();
  

@override final  ErrorKind kind;
/// Given when the error is thrown; the Problems list finds it by this.
@override@JsonKey() final  int id;
/// What did not happen, with its object: `You can’t deploy
/// pump-control`. Composed from [kind], [call], [thing] and [site].
@override@JsonKey() final  String title;
/// The broker's words, as they came; empty when it sent none (a
/// timeout). For a fault in Studio: what happened, in Studio's words.
@override@JsonKey() final  String message;
/// The status of the refusal; null for Studio's own faults and for a
/// `{success: false}` answer.
@override final  StatusCode? status;
/// The full key the call was made on.
@override final  String? key;
/// The call: `deploy`, `set`, `subscribe`, `history`, `list`, …
@override final  String? call;
/// The name of what the call was about (`pump-control`, `modbus
/// 0.4.2`), for the title; the last segment of [key] when null.
@override final  String? thing;
/// The site the call went to.
@override final  String? site;
/// When it failed, local time.
@override final  DateTime? at;
/// Nobody was waiting for this call: a toast and a line in Problems, no
/// dialog.
@override@JsonKey() final  bool quiet;
/// The call changes something on the broker (`set`, `deploy`, an
/// action): a timeout then warns that it may have been applied.
@override@JsonKey() final  bool write;
/// Builds the action to dispatch again (*Try again*); null when the
/// call cannot be repeated as it was.
@override final  Object Function()? retry;
/// Builds the load action of the screen it came from (*Refresh*).
@override final  Object Function()? reload;
/// The parameter an `invalid_parameter` names, when the broker named
/// one.
@override final  String? field;
/// Studio faults only.
@override final  FaultReport? report;
/// Opened as a dialog (the drawer says so).
@override@JsonKey() final  bool shown;
/// A live stream of this site went down: its toast stays until the
/// stream is open again.
@override final  String? stream;
/// The seconds *Try again* waits for (`busy`), when the broker gave a
/// hint; null for the default.
@override final  int? wait;

/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioErrorCopyWith<_StudioError> get copyWith => __$StudioErrorCopyWithImpl<_StudioError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioError&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.status, status) || other.status == status)&&(identical(other.key, key) || other.key == key)&&(identical(other.call, call) || other.call == call)&&(identical(other.thing, thing) || other.thing == thing)&&(identical(other.site, site) || other.site == site)&&(identical(other.at, at) || other.at == at)&&(identical(other.quiet, quiet) || other.quiet == quiet)&&(identical(other.write, write) || other.write == write)&&(identical(other.retry, retry) || other.retry == retry)&&(identical(other.reload, reload) || other.reload == reload)&&(identical(other.field, field) || other.field == field)&&(identical(other.report, report) || other.report == report)&&(identical(other.shown, shown) || other.shown == shown)&&(identical(other.stream, stream) || other.stream == stream)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,kind,id,title,message,status,key,call,thing,site,at,quiet,write,retry,reload,field,report,shown,stream,wait]);
}

@override
String toString() {
    return 'StudioError(kind: $kind, id: $id, title: $title, message: $message, status: $status, key: $key, call: $call, thing: $thing, site: $site, at: $at, quiet: $quiet, write: $write, retry: $retry, reload: $reload, field: $field, report: $report, shown: $shown, stream: $stream, wait: $wait)';
}


}

/// @nodoc
abstract mixin class _$StudioErrorCopyWith<$Res> implements $StudioErrorCopyWith<$Res> {
  factory _$StudioErrorCopyWith(_StudioError value, $Res Function(_StudioError) _then) = __$StudioErrorCopyWithImpl;
@override @useResult
$Res call({
 ErrorKind kind, int id, String title, String message, StatusCode? status, String? key, String? call, String? thing, String? site, DateTime? at, bool quiet, bool write, Object Function()? retry, Object Function()? reload, String? field, FaultReport? report, bool shown, String? stream, int? wait
});


@override $FaultReportCopyWith<$Res>? get report;

}
/// @nodoc
class __$StudioErrorCopyWithImpl<$Res>
    implements _$StudioErrorCopyWith<$Res> {
  __$StudioErrorCopyWithImpl(this._self, this._then);

  final _StudioError _self;
  final $Res Function(_StudioError) _then;

/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? id = null,Object? title = null,Object? message = null,Object? status = freezed,Object? key = freezed,Object? call = freezed,Object? thing = freezed,Object? site = freezed,Object? at = freezed,Object? quiet = null,Object? write = null,Object? retry = freezed,Object? reload = freezed,Object? field = freezed,Object? report = freezed,Object? shown = null,Object? stream = freezed,Object? wait = freezed,}) {
  return _then(_StudioError(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ErrorKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StatusCode?,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,call: freezed == call ? _self.call : call // ignore: cast_nullable_to_non_nullable
as String?,thing: freezed == thing ? _self.thing : thing // ignore: cast_nullable_to_non_nullable
as String?,site: freezed == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String?,at: freezed == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime?,quiet: null == quiet ? _self.quiet : quiet // ignore: cast_nullable_to_non_nullable
as bool,write: null == write ? _self.write : write // ignore: cast_nullable_to_non_nullable
as bool,retry: freezed == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as Object Function()?,reload: freezed == reload ? _self.reload : reload // ignore: cast_nullable_to_non_nullable
as Object Function()?,field: freezed == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String?,report: freezed == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as FaultReport?,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,stream: freezed == stream ? _self.stream : stream // ignore: cast_nullable_to_non_nullable
as String?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of StudioError
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FaultReportCopyWith<$Res>? get report {
    if (_self.report == null) {
    return null;
  }

  return $FaultReportCopyWith<$Res>(_self.report!, (value) {
    return _then(_self.copyWith(report: value));
  });
}
}

// dart format on
