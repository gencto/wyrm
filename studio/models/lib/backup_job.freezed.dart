// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_job.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupJob {

 String get id;/// `full`, `link`, `pre-update` or `pre-restore`.
 String get kind;/// The file name.
 String get name; IList<String> get sections;/// How its secrets are sealed: `none`, `passphrase` or `broker`.
 String get sealed;/// The link of a link backup.
 String get link;/// Who made it.
 String get by;/// `running`, `done` or `failed`.
 String get status;/// Percent.
 int get progress; String get step;/// Bytes.
 int get size; String get sha256;/// ISO 8601, UTC.
 String get created; String get expires; String get error; String get sentTo;/// `sending`, `done` or `failed`; empty when never sent.
 String get sendStatus; int get sendProgress; String get sendError;
/// Create a copy of BackupJob
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupJobCopyWith<BackupJob> get copyWith => _$BackupJobCopyWithImpl<BackupJob>(this as BackupJob, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BackupJob;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupJob&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.sections, _this.sections)&&(identical(other.sealed, _this.sealed) || other.sealed == _this.sealed)&&(identical(other.link, _this.link) || other.link == _this.link)&&(identical(other.by, _this.by) || other.by == _this.by)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256)&&(identical(other.created, _this.created) || other.created == _this.created)&&(identical(other.expires, _this.expires) || other.expires == _this.expires)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.sentTo, _this.sentTo) || other.sentTo == _this.sentTo)&&(identical(other.sendStatus, _this.sendStatus) || other.sendStatus == _this.sendStatus)&&(identical(other.sendProgress, _this.sendProgress) || other.sendProgress == _this.sendProgress)&&(identical(other.sendError, _this.sendError) || other.sendError == _this.sendError));
}


@override
int get hashCode {
  final _this = this as BackupJob;
  return Object.hashAll([runtimeType,_this.id,_this.kind,_this.name,const DeepCollectionEquality().hash(_this.sections),_this.sealed,_this.link,_this.by,_this.status,_this.progress,_this.step,_this.size,_this.sha256,_this.created,_this.expires,_this.error,_this.sentTo,_this.sendStatus,_this.sendProgress,_this.sendError]);
}

@override
String toString() {
  final _this = this as BackupJob;
  return 'BackupJob(id: ${_this.id}, kind: ${_this.kind}, name: ${_this.name}, sections: ${_this.sections}, sealed: ${_this.sealed}, link: ${_this.link}, by: ${_this.by}, status: ${_this.status}, progress: ${_this.progress}, step: ${_this.step}, size: ${_this.size}, sha256: ${_this.sha256}, created: ${_this.created}, expires: ${_this.expires}, error: ${_this.error}, sentTo: ${_this.sentTo}, sendStatus: ${_this.sendStatus}, sendProgress: ${_this.sendProgress}, sendError: ${_this.sendError})';
}


}

/// @nodoc
abstract mixin class $BackupJobCopyWith<$Res>  {
  factory $BackupJobCopyWith(BackupJob value, $Res Function(BackupJob) _then) = _$BackupJobCopyWithImpl;
@useResult
$Res call({
 String id, String kind, String name, IList<String> sections, String sealed, String link, String by, String status, int progress, String step, int size, String sha256, String created, String expires, String error, String sentTo, String sendStatus, int sendProgress, String sendError
});




}
/// @nodoc
class _$BackupJobCopyWithImpl<$Res>
    implements $BackupJobCopyWith<$Res> {
  _$BackupJobCopyWithImpl(this._self, this._then);

  final BackupJob _self;
  final $Res Function(BackupJob) _then;

/// Create a copy of BackupJob
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? name = null,Object? sections = null,Object? sealed = null,Object? link = null,Object? by = null,Object? status = null,Object? progress = null,Object? step = null,Object? size = null,Object? sha256 = null,Object? created = null,Object? expires = null,Object? error = null,Object? sentTo = null,Object? sendStatus = null,Object? sendProgress = null,Object? sendError = null,}) {
  return _then(BackupJob(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<String>,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as String,link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String,by: null == by ? _self.by : by // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as String,expires: null == expires ? _self.expires : expires // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,sentTo: null == sentTo ? _self.sentTo : sentTo // ignore: cast_nullable_to_non_nullable
as String,sendStatus: null == sendStatus ? _self.sendStatus : sendStatus // ignore: cast_nullable_to_non_nullable
as String,sendProgress: null == sendProgress ? _self.sendProgress : sendProgress // ignore: cast_nullable_to_non_nullable
as int,sendError: null == sendError ? _self.sendError : sendError // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _BackupJob implements BackupJob {
  const _BackupJob({required this.id, this.kind = 'full', this.name = '', this.sections = const IListConst([]), this.sealed = 'none', this.link = '', this.by = '', this.status = '', this.progress = 0, this.step = '', this.size = 0, this.sha256 = '', this.created = '', this.expires = '', this.error = '', this.sentTo = '', this.sendStatus = '', this.sendProgress = 0, this.sendError = ''});
  

@override final  String id;
/// `full`, `link`, `pre-update` or `pre-restore`.
@override@JsonKey() final  String kind;
/// The file name.
@override@JsonKey() final  String name;
@override@JsonKey() final  IList<String> sections;
/// How its secrets are sealed: `none`, `passphrase` or `broker`.
@override@JsonKey() final  String sealed;
/// The link of a link backup.
@override@JsonKey() final  String link;
/// Who made it.
@override@JsonKey() final  String by;
/// `running`, `done` or `failed`.
@override@JsonKey() final  String status;
/// Percent.
@override@JsonKey() final  int progress;
@override@JsonKey() final  String step;
/// Bytes.
@override@JsonKey() final  int size;
@override@JsonKey() final  String sha256;
/// ISO 8601, UTC.
@override@JsonKey() final  String created;
@override@JsonKey() final  String expires;
@override@JsonKey() final  String error;
@override@JsonKey() final  String sentTo;
/// `sending`, `done` or `failed`; empty when never sent.
@override@JsonKey() final  String sendStatus;
@override@JsonKey() final  int sendProgress;
@override@JsonKey() final  String sendError;

/// Create a copy of BackupJob
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupJobCopyWith<_BackupJob> get copyWith => __$BackupJobCopyWithImpl<_BackupJob>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupJob&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.sections, sections)&&(identical(other.sealed, sealed) || other.sealed == sealed)&&(identical(other.link, link) || other.link == link)&&(identical(other.by, by) || other.by == by)&&(identical(other.status, status) || other.status == status)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.step, step) || other.step == step)&&(identical(other.size, size) || other.size == size)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.created, created) || other.created == created)&&(identical(other.expires, expires) || other.expires == expires)&&(identical(other.error, error) || other.error == error)&&(identical(other.sentTo, sentTo) || other.sentTo == sentTo)&&(identical(other.sendStatus, sendStatus) || other.sendStatus == sendStatus)&&(identical(other.sendProgress, sendProgress) || other.sendProgress == sendProgress)&&(identical(other.sendError, sendError) || other.sendError == sendError));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,id,kind,name,const DeepCollectionEquality().hash(sections),sealed,link,by,status,progress,step,size,sha256,created,expires,error,sentTo,sendStatus,sendProgress,sendError]);
}

@override
String toString() {
    return 'BackupJob(id: $id, kind: $kind, name: $name, sections: $sections, sealed: $sealed, link: $link, by: $by, status: $status, progress: $progress, step: $step, size: $size, sha256: $sha256, created: $created, expires: $expires, error: $error, sentTo: $sentTo, sendStatus: $sendStatus, sendProgress: $sendProgress, sendError: $sendError)';
}


}

/// @nodoc
abstract mixin class _$BackupJobCopyWith<$Res> implements $BackupJobCopyWith<$Res> {
  factory _$BackupJobCopyWith(_BackupJob value, $Res Function(_BackupJob) _then) = __$BackupJobCopyWithImpl;
@override @useResult
$Res call({
 String id, String kind, String name, IList<String> sections, String sealed, String link, String by, String status, int progress, String step, int size, String sha256, String created, String expires, String error, String sentTo, String sendStatus, int sendProgress, String sendError
});




}
/// @nodoc
class __$BackupJobCopyWithImpl<$Res>
    implements _$BackupJobCopyWith<$Res> {
  __$BackupJobCopyWithImpl(this._self, this._then);

  final _BackupJob _self;
  final $Res Function(_BackupJob) _then;

/// Create a copy of BackupJob
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? name = null,Object? sections = null,Object? sealed = null,Object? link = null,Object? by = null,Object? status = null,Object? progress = null,Object? step = null,Object? size = null,Object? sha256 = null,Object? created = null,Object? expires = null,Object? error = null,Object? sentTo = null,Object? sendStatus = null,Object? sendProgress = null,Object? sendError = null,}) {
  return _then(_BackupJob(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<String>,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as String,link: null == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String,by: null == by ? _self.by : by // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as String,expires: null == expires ? _self.expires : expires // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,sentTo: null == sentTo ? _self.sentTo : sentTo // ignore: cast_nullable_to_non_nullable
as String,sendStatus: null == sendStatus ? _self.sendStatus : sendStatus // ignore: cast_nullable_to_non_nullable
as String,sendProgress: null == sendProgress ? _self.sendProgress : sendProgress // ignore: cast_nullable_to_non_nullable
as int,sendError: null == sendError ? _self.sendError : sendError // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
