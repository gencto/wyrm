// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backups_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupsState {

 IMap<String, BackupJob> get table; IList<String> get view; bool get exportSecrets; IList<SendLink> get sendLinks; IList<String> get sections; int get keepDays; String? get stage; String? get link; ISet<String> get chosen; int? get historyDays; ISet<String> get offLinks; String get where; String? get sendLink; String? get sendConnection; String? get sendPath; IList<String> get connections; IMap<String, int> get estimate; String? get job; String? get downloading; int get downloaded; String? get upload; String? get uploadName; int get uploadSize; int get uploaded; RestoreCheck? get check; String get mode; bool get replaceKeys; bool get acceptRights; String? get result; IMap<String, String> get saved;
/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupsStateCopyWith<BackupsState> get copyWith => _$BackupsStateCopyWithImpl<BackupsState>(this as BackupsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BackupsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupsState&&(identical(other.table, _this.table) || other.table == _this.table)&&const DeepCollectionEquality().equals(other.view, _this.view)&&(identical(other.exportSecrets, _this.exportSecrets) || other.exportSecrets == _this.exportSecrets)&&const DeepCollectionEquality().equals(other.sendLinks, _this.sendLinks)&&const DeepCollectionEquality().equals(other.sections, _this.sections)&&(identical(other.keepDays, _this.keepDays) || other.keepDays == _this.keepDays)&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.link, _this.link) || other.link == _this.link)&&const DeepCollectionEquality().equals(other.chosen, _this.chosen)&&(identical(other.historyDays, _this.historyDays) || other.historyDays == _this.historyDays)&&const DeepCollectionEquality().equals(other.offLinks, _this.offLinks)&&(identical(other.where, _this.where) || other.where == _this.where)&&(identical(other.sendLink, _this.sendLink) || other.sendLink == _this.sendLink)&&(identical(other.sendConnection, _this.sendConnection) || other.sendConnection == _this.sendConnection)&&(identical(other.sendPath, _this.sendPath) || other.sendPath == _this.sendPath)&&const DeepCollectionEquality().equals(other.connections, _this.connections)&&(identical(other.estimate, _this.estimate) || other.estimate == _this.estimate)&&(identical(other.job, _this.job) || other.job == _this.job)&&(identical(other.downloading, _this.downloading) || other.downloading == _this.downloading)&&(identical(other.downloaded, _this.downloaded) || other.downloaded == _this.downloaded)&&(identical(other.upload, _this.upload) || other.upload == _this.upload)&&(identical(other.uploadName, _this.uploadName) || other.uploadName == _this.uploadName)&&(identical(other.uploadSize, _this.uploadSize) || other.uploadSize == _this.uploadSize)&&(identical(other.uploaded, _this.uploaded) || other.uploaded == _this.uploaded)&&(identical(other.check, _this.check) || other.check == _this.check)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.replaceKeys, _this.replaceKeys) || other.replaceKeys == _this.replaceKeys)&&(identical(other.acceptRights, _this.acceptRights) || other.acceptRights == _this.acceptRights)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.saved, _this.saved) || other.saved == _this.saved));
}


@override
int get hashCode {
  final _this = this as BackupsState;
  return Object.hashAll([runtimeType,_this.table,const DeepCollectionEquality().hash(_this.view),_this.exportSecrets,const DeepCollectionEquality().hash(_this.sendLinks),const DeepCollectionEquality().hash(_this.sections),_this.keepDays,_this.stage,_this.link,const DeepCollectionEquality().hash(_this.chosen),_this.historyDays,const DeepCollectionEquality().hash(_this.offLinks),_this.where,_this.sendLink,_this.sendConnection,_this.sendPath,const DeepCollectionEquality().hash(_this.connections),_this.estimate,_this.job,_this.downloading,_this.downloaded,_this.upload,_this.uploadName,_this.uploadSize,_this.uploaded,_this.check,_this.mode,_this.replaceKeys,_this.acceptRights,_this.result,_this.saved]);
}

@override
String toString() {
  final _this = this as BackupsState;
  return 'BackupsState(table: ${_this.table}, view: ${_this.view}, exportSecrets: ${_this.exportSecrets}, sendLinks: ${_this.sendLinks}, sections: ${_this.sections}, keepDays: ${_this.keepDays}, stage: ${_this.stage}, link: ${_this.link}, chosen: ${_this.chosen}, historyDays: ${_this.historyDays}, offLinks: ${_this.offLinks}, where: ${_this.where}, sendLink: ${_this.sendLink}, sendConnection: ${_this.sendConnection}, sendPath: ${_this.sendPath}, connections: ${_this.connections}, estimate: ${_this.estimate}, job: ${_this.job}, downloading: ${_this.downloading}, downloaded: ${_this.downloaded}, upload: ${_this.upload}, uploadName: ${_this.uploadName}, uploadSize: ${_this.uploadSize}, uploaded: ${_this.uploaded}, check: ${_this.check}, mode: ${_this.mode}, replaceKeys: ${_this.replaceKeys}, acceptRights: ${_this.acceptRights}, result: ${_this.result}, saved: ${_this.saved})';
}


}

/// @nodoc
abstract mixin class $BackupsStateCopyWith<$Res>  {
  factory $BackupsStateCopyWith(BackupsState value, $Res Function(BackupsState) _then) = _$BackupsStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, BackupJob> table, IList<String> view, bool exportSecrets, IList<SendLink> sendLinks, IList<String> sections, int keepDays, String? stage, String? link, ISet<String> chosen, int? historyDays, ISet<String> offLinks, String where, String? sendLink, String? sendConnection, String? sendPath, IList<String> connections, IMap<String, int> estimate, String? job, String? downloading, int downloaded, String? upload, String? uploadName, int uploadSize, int uploaded, RestoreCheck? check, String mode, bool replaceKeys, bool acceptRights, String? result, IMap<String, String> saved
});


$RestoreCheckCopyWith<$Res>? get check;

}
/// @nodoc
class _$BackupsStateCopyWithImpl<$Res>
    implements $BackupsStateCopyWith<$Res> {
  _$BackupsStateCopyWithImpl(this._self, this._then);

  final BackupsState _self;
  final $Res Function(BackupsState) _then;

/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? exportSecrets = null,Object? sendLinks = null,Object? sections = null,Object? keepDays = null,Object? stage = freezed,Object? link = freezed,Object? chosen = null,Object? historyDays = freezed,Object? offLinks = null,Object? where = null,Object? sendLink = freezed,Object? sendConnection = freezed,Object? sendPath = freezed,Object? connections = null,Object? estimate = null,Object? job = freezed,Object? downloading = freezed,Object? downloaded = null,Object? upload = freezed,Object? uploadName = freezed,Object? uploadSize = null,Object? uploaded = null,Object? check = freezed,Object? mode = null,Object? replaceKeys = null,Object? acceptRights = null,Object? result = freezed,Object? saved = null,}) {
  return _then(BackupsState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, BackupJob>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,exportSecrets: null == exportSecrets ? _self.exportSecrets : exportSecrets // ignore: cast_nullable_to_non_nullable
as bool,sendLinks: null == sendLinks ? _self.sendLinks : sendLinks // ignore: cast_nullable_to_non_nullable
as IList<SendLink>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<String>,keepDays: null == keepDays ? _self.keepDays : keepDays // ignore: cast_nullable_to_non_nullable
as int,stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,link: freezed == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String?,chosen: null == chosen ? _self.chosen : chosen // ignore: cast_nullable_to_non_nullable
as ISet<String>,historyDays: freezed == historyDays ? _self.historyDays : historyDays // ignore: cast_nullable_to_non_nullable
as int?,offLinks: null == offLinks ? _self.offLinks : offLinks // ignore: cast_nullable_to_non_nullable
as ISet<String>,where: null == where ? _self.where : where // ignore: cast_nullable_to_non_nullable
as String,sendLink: freezed == sendLink ? _self.sendLink : sendLink // ignore: cast_nullable_to_non_nullable
as String?,sendConnection: freezed == sendConnection ? _self.sendConnection : sendConnection // ignore: cast_nullable_to_non_nullable
as String?,sendPath: freezed == sendPath ? _self.sendPath : sendPath // ignore: cast_nullable_to_non_nullable
as String?,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as IList<String>,estimate: null == estimate ? _self.estimate : estimate // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,job: freezed == job ? _self.job : job // ignore: cast_nullable_to_non_nullable
as String?,downloading: freezed == downloading ? _self.downloading : downloading // ignore: cast_nullable_to_non_nullable
as String?,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,upload: freezed == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as String?,uploadName: freezed == uploadName ? _self.uploadName : uploadName // ignore: cast_nullable_to_non_nullable
as String?,uploadSize: null == uploadSize ? _self.uploadSize : uploadSize // ignore: cast_nullable_to_non_nullable
as int,uploaded: null == uploaded ? _self.uploaded : uploaded // ignore: cast_nullable_to_non_nullable
as int,check: freezed == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as RestoreCheck?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,replaceKeys: null == replaceKeys ? _self.replaceKeys : replaceKeys // ignore: cast_nullable_to_non_nullable
as bool,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}
/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RestoreCheckCopyWith<$Res>? get check {
    if (_self.check == null) {
    return null;
  }

  return $RestoreCheckCopyWith<$Res>(_self.check!, (value) {
    return _then(_self.copyWith(check: value));
  });
}
}



/// @nodoc


class _BackupsState implements BackupsState {
  const _BackupsState({this.table = const IMapConst({}), this.view = const IListConst([]), this.exportSecrets = false, this.sendLinks = const IListConst([]), this.sections = const IListConst([]), this.keepDays = 7, this.stage, this.link, this.chosen = const ISetConst({}), this.historyDays, this.offLinks = const ISetConst({}), this.where = 'computer', this.sendLink, this.sendConnection, this.sendPath, this.connections = const IListConst([]), this.estimate = const IMapConst({}), this.job, this.downloading, this.downloaded = 0, this.upload, this.uploadName, this.uploadSize = 0, this.uploaded = 0, this.check, this.mode = 'add', this.replaceKeys = false, this.acceptRights = false, this.result, this.saved = const IMapConst({})});
  

@override@JsonKey() final  IMap<String, BackupJob> table;
@override@JsonKey() final  IList<String> view;
@override@JsonKey() final  bool exportSecrets;
@override@JsonKey() final  IList<SendLink> sendLinks;
@override@JsonKey() final  IList<String> sections;
@override@JsonKey() final  int keepDays;
@override final  String? stage;
@override final  String? link;
@override@JsonKey() final  ISet<String> chosen;
@override final  int? historyDays;
@override@JsonKey() final  ISet<String> offLinks;
@override@JsonKey() final  String where;
@override final  String? sendLink;
@override final  String? sendConnection;
@override final  String? sendPath;
@override@JsonKey() final  IList<String> connections;
@override@JsonKey() final  IMap<String, int> estimate;
@override final  String? job;
@override final  String? downloading;
@override@JsonKey() final  int downloaded;
@override final  String? upload;
@override final  String? uploadName;
@override@JsonKey() final  int uploadSize;
@override@JsonKey() final  int uploaded;
@override final  RestoreCheck? check;
@override@JsonKey() final  String mode;
@override@JsonKey() final  bool replaceKeys;
@override@JsonKey() final  bool acceptRights;
@override final  String? result;
@override@JsonKey() final  IMap<String, String> saved;

/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupsStateCopyWith<_BackupsState> get copyWith => __$BackupsStateCopyWithImpl<_BackupsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupsState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.exportSecrets, exportSecrets) || other.exportSecrets == exportSecrets)&&const DeepCollectionEquality().equals(other.sendLinks, sendLinks)&&const DeepCollectionEquality().equals(other.sections, sections)&&(identical(other.keepDays, keepDays) || other.keepDays == keepDays)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.link, link) || other.link == link)&&const DeepCollectionEquality().equals(other.chosen, chosen)&&(identical(other.historyDays, historyDays) || other.historyDays == historyDays)&&const DeepCollectionEquality().equals(other.offLinks, offLinks)&&(identical(other.where, where) || other.where == where)&&(identical(other.sendLink, sendLink) || other.sendLink == sendLink)&&(identical(other.sendConnection, sendConnection) || other.sendConnection == sendConnection)&&(identical(other.sendPath, sendPath) || other.sendPath == sendPath)&&const DeepCollectionEquality().equals(other.connections, connections)&&(identical(other.estimate, estimate) || other.estimate == estimate)&&(identical(other.job, job) || other.job == job)&&(identical(other.downloading, downloading) || other.downloading == downloading)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.uploadName, uploadName) || other.uploadName == uploadName)&&(identical(other.uploadSize, uploadSize) || other.uploadSize == uploadSize)&&(identical(other.uploaded, uploaded) || other.uploaded == uploaded)&&(identical(other.check, check) || other.check == check)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.replaceKeys, replaceKeys) || other.replaceKeys == replaceKeys)&&(identical(other.acceptRights, acceptRights) || other.acceptRights == acceptRights)&&(identical(other.result, result) || other.result == result)&&(identical(other.saved, saved) || other.saved == saved));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,table,const DeepCollectionEquality().hash(view),exportSecrets,const DeepCollectionEquality().hash(sendLinks),const DeepCollectionEquality().hash(sections),keepDays,stage,link,const DeepCollectionEquality().hash(chosen),historyDays,const DeepCollectionEquality().hash(offLinks),where,sendLink,sendConnection,sendPath,const DeepCollectionEquality().hash(connections),estimate,job,downloading,downloaded,upload,uploadName,uploadSize,uploaded,check,mode,replaceKeys,acceptRights,result,saved]);
}

@override
String toString() {
    return 'BackupsState(table: $table, view: $view, exportSecrets: $exportSecrets, sendLinks: $sendLinks, sections: $sections, keepDays: $keepDays, stage: $stage, link: $link, chosen: $chosen, historyDays: $historyDays, offLinks: $offLinks, where: $where, sendLink: $sendLink, sendConnection: $sendConnection, sendPath: $sendPath, connections: $connections, estimate: $estimate, job: $job, downloading: $downloading, downloaded: $downloaded, upload: $upload, uploadName: $uploadName, uploadSize: $uploadSize, uploaded: $uploaded, check: $check, mode: $mode, replaceKeys: $replaceKeys, acceptRights: $acceptRights, result: $result, saved: $saved)';
}


}

/// @nodoc
abstract mixin class _$BackupsStateCopyWith<$Res> implements $BackupsStateCopyWith<$Res> {
  factory _$BackupsStateCopyWith(_BackupsState value, $Res Function(_BackupsState) _then) = __$BackupsStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, BackupJob> table, IList<String> view, bool exportSecrets, IList<SendLink> sendLinks, IList<String> sections, int keepDays, String? stage, String? link, ISet<String> chosen, int? historyDays, ISet<String> offLinks, String where, String? sendLink, String? sendConnection, String? sendPath, IList<String> connections, IMap<String, int> estimate, String? job, String? downloading, int downloaded, String? upload, String? uploadName, int uploadSize, int uploaded, RestoreCheck? check, String mode, bool replaceKeys, bool acceptRights, String? result, IMap<String, String> saved
});


@override $RestoreCheckCopyWith<$Res>? get check;

}
/// @nodoc
class __$BackupsStateCopyWithImpl<$Res>
    implements _$BackupsStateCopyWith<$Res> {
  __$BackupsStateCopyWithImpl(this._self, this._then);

  final _BackupsState _self;
  final $Res Function(_BackupsState) _then;

/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? exportSecrets = null,Object? sendLinks = null,Object? sections = null,Object? keepDays = null,Object? stage = freezed,Object? link = freezed,Object? chosen = null,Object? historyDays = freezed,Object? offLinks = null,Object? where = null,Object? sendLink = freezed,Object? sendConnection = freezed,Object? sendPath = freezed,Object? connections = null,Object? estimate = null,Object? job = freezed,Object? downloading = freezed,Object? downloaded = null,Object? upload = freezed,Object? uploadName = freezed,Object? uploadSize = null,Object? uploaded = null,Object? check = freezed,Object? mode = null,Object? replaceKeys = null,Object? acceptRights = null,Object? result = freezed,Object? saved = null,}) {
  return _then(_BackupsState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, BackupJob>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,exportSecrets: null == exportSecrets ? _self.exportSecrets : exportSecrets // ignore: cast_nullable_to_non_nullable
as bool,sendLinks: null == sendLinks ? _self.sendLinks : sendLinks // ignore: cast_nullable_to_non_nullable
as IList<SendLink>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<String>,keepDays: null == keepDays ? _self.keepDays : keepDays // ignore: cast_nullable_to_non_nullable
as int,stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,link: freezed == link ? _self.link : link // ignore: cast_nullable_to_non_nullable
as String?,chosen: null == chosen ? _self.chosen : chosen // ignore: cast_nullable_to_non_nullable
as ISet<String>,historyDays: freezed == historyDays ? _self.historyDays : historyDays // ignore: cast_nullable_to_non_nullable
as int?,offLinks: null == offLinks ? _self.offLinks : offLinks // ignore: cast_nullable_to_non_nullable
as ISet<String>,where: null == where ? _self.where : where // ignore: cast_nullable_to_non_nullable
as String,sendLink: freezed == sendLink ? _self.sendLink : sendLink // ignore: cast_nullable_to_non_nullable
as String?,sendConnection: freezed == sendConnection ? _self.sendConnection : sendConnection // ignore: cast_nullable_to_non_nullable
as String?,sendPath: freezed == sendPath ? _self.sendPath : sendPath // ignore: cast_nullable_to_non_nullable
as String?,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as IList<String>,estimate: null == estimate ? _self.estimate : estimate // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,job: freezed == job ? _self.job : job // ignore: cast_nullable_to_non_nullable
as String?,downloading: freezed == downloading ? _self.downloading : downloading // ignore: cast_nullable_to_non_nullable
as String?,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,upload: freezed == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as String?,uploadName: freezed == uploadName ? _self.uploadName : uploadName // ignore: cast_nullable_to_non_nullable
as String?,uploadSize: null == uploadSize ? _self.uploadSize : uploadSize // ignore: cast_nullable_to_non_nullable
as int,uploaded: null == uploaded ? _self.uploaded : uploaded // ignore: cast_nullable_to_non_nullable
as int,check: freezed == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as RestoreCheck?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,replaceKeys: null == replaceKeys ? _self.replaceKeys : replaceKeys // ignore: cast_nullable_to_non_nullable
as bool,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}

/// Create a copy of BackupsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RestoreCheckCopyWith<$Res>? get check {
    if (_self.check == null) {
    return null;
  }

  return $RestoreCheckCopyWith<$Res>(_self.check!, (value) {
    return _then(_self.copyWith(check: value));
  });
}
}

// dart format on
