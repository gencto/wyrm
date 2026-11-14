// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateReport {

 String get from; String get to;/// Unix seconds, the broker's clock.
 int get at;/// `checking` while the health check runs, then `ok`, `rolled_back` or
/// `failed`.
 String get result; int get kept; int get added; int get gone;/// `<link>/<path>`, at most 200 each.
 IList<String> get newKeys; IList<String> get goneKeys; String get reason; IList<String> get links; bool get changesState; bool get restorePoint;
/// Create a copy of UpdateReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateReportCopyWith<UpdateReport> get copyWith => _$UpdateReportCopyWithImpl<UpdateReport>(this as UpdateReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateReport&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.to, _this.to) || other.to == _this.to)&&(identical(other.at, _this.at) || other.at == _this.at)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.kept, _this.kept) || other.kept == _this.kept)&&(identical(other.added, _this.added) || other.added == _this.added)&&(identical(other.gone, _this.gone) || other.gone == _this.gone)&&const DeepCollectionEquality().equals(other.newKeys, _this.newKeys)&&const DeepCollectionEquality().equals(other.goneKeys, _this.goneKeys)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&const DeepCollectionEquality().equals(other.links, _this.links)&&(identical(other.changesState, _this.changesState) || other.changesState == _this.changesState)&&(identical(other.restorePoint, _this.restorePoint) || other.restorePoint == _this.restorePoint));
}


@override
int get hashCode {
  final _this = this as UpdateReport;
  return Object.hash(runtimeType,_this.from,_this.to,_this.at,_this.result,_this.kept,_this.added,_this.gone,const DeepCollectionEquality().hash(_this.newKeys),const DeepCollectionEquality().hash(_this.goneKeys),_this.reason,const DeepCollectionEquality().hash(_this.links),_this.changesState,_this.restorePoint);
}

@override
String toString() {
  final _this = this as UpdateReport;
  return 'UpdateReport(from: ${_this.from}, to: ${_this.to}, at: ${_this.at}, result: ${_this.result}, kept: ${_this.kept}, added: ${_this.added}, gone: ${_this.gone}, newKeys: ${_this.newKeys}, goneKeys: ${_this.goneKeys}, reason: ${_this.reason}, links: ${_this.links}, changesState: ${_this.changesState}, restorePoint: ${_this.restorePoint})';
}


}

/// @nodoc
abstract mixin class $UpdateReportCopyWith<$Res>  {
  factory $UpdateReportCopyWith(UpdateReport value, $Res Function(UpdateReport) _then) = _$UpdateReportCopyWithImpl;
@useResult
$Res call({
 String from, String to, int at, String result, int kept, int added, int gone, IList<String> newKeys, IList<String> goneKeys, String reason, IList<String> links, bool changesState, bool restorePoint
});




}
/// @nodoc
class _$UpdateReportCopyWithImpl<$Res>
    implements $UpdateReportCopyWith<$Res> {
  _$UpdateReportCopyWithImpl(this._self, this._then);

  final UpdateReport _self;
  final $Res Function(UpdateReport) _then;

/// Create a copy of UpdateReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? from = null,Object? to = null,Object? at = null,Object? result = null,Object? kept = null,Object? added = null,Object? gone = null,Object? newKeys = null,Object? goneKeys = null,Object? reason = null,Object? links = null,Object? changesState = null,Object? restorePoint = null,}) {
  return _then(UpdateReport(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,kept: null == kept ? _self.kept : kept // ignore: cast_nullable_to_non_nullable
as int,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,gone: null == gone ? _self.gone : gone // ignore: cast_nullable_to_non_nullable
as int,newKeys: null == newKeys ? _self.newKeys : newKeys // ignore: cast_nullable_to_non_nullable
as IList<String>,goneKeys: null == goneKeys ? _self.goneKeys : goneKeys // ignore: cast_nullable_to_non_nullable
as IList<String>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,links: null == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as IList<String>,changesState: null == changesState ? _self.changesState : changesState // ignore: cast_nullable_to_non_nullable
as bool,restorePoint: null == restorePoint ? _self.restorePoint : restorePoint // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _UpdateReport implements UpdateReport {
  const _UpdateReport({this.from = '', this.to = '', this.at = 0, this.result = '', this.kept = 0, this.added = 0, this.gone = 0, this.newKeys = const IListConst([]), this.goneKeys = const IListConst([]), this.reason = '', this.links = const IListConst([]), this.changesState = false, this.restorePoint = false});
  

@override@JsonKey() final  String from;
@override@JsonKey() final  String to;
/// Unix seconds, the broker's clock.
@override@JsonKey() final  int at;
/// `checking` while the health check runs, then `ok`, `rolled_back` or
/// `failed`.
@override@JsonKey() final  String result;
@override@JsonKey() final  int kept;
@override@JsonKey() final  int added;
@override@JsonKey() final  int gone;
/// `<link>/<path>`, at most 200 each.
@override@JsonKey() final  IList<String> newKeys;
@override@JsonKey() final  IList<String> goneKeys;
@override@JsonKey() final  String reason;
@override@JsonKey() final  IList<String> links;
@override@JsonKey() final  bool changesState;
@override@JsonKey() final  bool restorePoint;

/// Create a copy of UpdateReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateReportCopyWith<_UpdateReport> get copyWith => __$UpdateReportCopyWithImpl<_UpdateReport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateReport&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.at, at) || other.at == at)&&(identical(other.result, result) || other.result == result)&&(identical(other.kept, kept) || other.kept == kept)&&(identical(other.added, added) || other.added == added)&&(identical(other.gone, gone) || other.gone == gone)&&const DeepCollectionEquality().equals(other.newKeys, newKeys)&&const DeepCollectionEquality().equals(other.goneKeys, goneKeys)&&(identical(other.reason, reason) || other.reason == reason)&&const DeepCollectionEquality().equals(other.links, links)&&(identical(other.changesState, changesState) || other.changesState == changesState)&&(identical(other.restorePoint, restorePoint) || other.restorePoint == restorePoint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,to,at,result,kept,added,gone,const DeepCollectionEquality().hash(newKeys),const DeepCollectionEquality().hash(goneKeys),reason,const DeepCollectionEquality().hash(links),changesState,restorePoint);
}

@override
String toString() {
    return 'UpdateReport(from: $from, to: $to, at: $at, result: $result, kept: $kept, added: $added, gone: $gone, newKeys: $newKeys, goneKeys: $goneKeys, reason: $reason, links: $links, changesState: $changesState, restorePoint: $restorePoint)';
}


}

/// @nodoc
abstract mixin class _$UpdateReportCopyWith<$Res> implements $UpdateReportCopyWith<$Res> {
  factory _$UpdateReportCopyWith(_UpdateReport value, $Res Function(_UpdateReport) _then) = __$UpdateReportCopyWithImpl;
@override @useResult
$Res call({
 String from, String to, int at, String result, int kept, int added, int gone, IList<String> newKeys, IList<String> goneKeys, String reason, IList<String> links, bool changesState, bool restorePoint
});




}
/// @nodoc
class __$UpdateReportCopyWithImpl<$Res>
    implements _$UpdateReportCopyWith<$Res> {
  __$UpdateReportCopyWithImpl(this._self, this._then);

  final _UpdateReport _self;
  final $Res Function(_UpdateReport) _then;

/// Create a copy of UpdateReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? from = null,Object? to = null,Object? at = null,Object? result = null,Object? kept = null,Object? added = null,Object? gone = null,Object? newKeys = null,Object? goneKeys = null,Object? reason = null,Object? links = null,Object? changesState = null,Object? restorePoint = null,}) {
  return _then(_UpdateReport(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,kept: null == kept ? _self.kept : kept // ignore: cast_nullable_to_non_nullable
as int,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,gone: null == gone ? _self.gone : gone // ignore: cast_nullable_to_non_nullable
as int,newKeys: null == newKeys ? _self.newKeys : newKeys // ignore: cast_nullable_to_non_nullable
as IList<String>,goneKeys: null == goneKeys ? _self.goneKeys : goneKeys // ignore: cast_nullable_to_non_nullable
as IList<String>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,links: null == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as IList<String>,changesState: null == changesState ? _self.changesState : changesState // ignore: cast_nullable_to_non_nullable
as bool,restorePoint: null == restorePoint ? _self.restorePoint : restorePoint // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
