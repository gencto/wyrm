// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_row.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogRow {

/// `driver:<code>` or `package:<code>`.
 String get id; String get title; String get summary; String get category; String get version; CatalogForm? get form; bool get official;
/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogRowCopyWith<CatalogRow> get copyWith => _$CatalogRowCopyWithImpl<CatalogRow>(this as CatalogRow, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogRow;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogRow&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.form, _this.form) || other.form == _this.form)&&(identical(other.official, _this.official) || other.official == _this.official));
}


@override
int get hashCode {
  final _this = this as CatalogRow;
  return Object.hash(runtimeType,_this.id,_this.title,_this.summary,_this.category,_this.version,_this.form,_this.official);
}

@override
String toString() {
  final _this = this as CatalogRow;
  return 'CatalogRow(id: ${_this.id}, title: ${_this.title}, summary: ${_this.summary}, category: ${_this.category}, version: ${_this.version}, form: ${_this.form}, official: ${_this.official})';
}


}

/// @nodoc
abstract mixin class $CatalogRowCopyWith<$Res>  {
  factory $CatalogRowCopyWith(CatalogRow value, $Res Function(CatalogRow) _then) = _$CatalogRowCopyWithImpl;
@useResult
$Res call({
 String id, String title, String summary, String category, String version, CatalogForm? form, bool official
});




}
/// @nodoc
class _$CatalogRowCopyWithImpl<$Res>
    implements $CatalogRowCopyWith<$Res> {
  _$CatalogRowCopyWithImpl(this._self, this._then);

  final CatalogRow _self;
  final $Res Function(CatalogRow) _then;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? summary = null,Object? category = null,Object? version = null,Object? form = freezed,Object? official = null,}) {
  return _then(CatalogRow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,form: freezed == form ? _self.form : form // ignore: cast_nullable_to_non_nullable
as CatalogForm?,official: null == official ? _self.official : official // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _CatalogRow implements CatalogRow {
  const _CatalogRow({required this.id, this.title = '', this.summary = '', this.category = '', this.version = '', this.form, this.official = false});
  

/// `driver:<code>` or `package:<code>`.
@override final  String id;
@override@JsonKey() final  String title;
@override@JsonKey() final  String summary;
@override@JsonKey() final  String category;
@override@JsonKey() final  String version;
@override final  CatalogForm? form;
@override@JsonKey() final  bool official;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogRowCopyWith<_CatalogRow> get copyWith => __$CatalogRowCopyWithImpl<_CatalogRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogRow&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.category, category) || other.category == category)&&(identical(other.version, version) || other.version == version)&&(identical(other.form, form) || other.form == form)&&(identical(other.official, official) || other.official == official));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,summary,category,version,form,official);
}

@override
String toString() {
    return 'CatalogRow(id: $id, title: $title, summary: $summary, category: $category, version: $version, form: $form, official: $official)';
}


}

/// @nodoc
abstract mixin class _$CatalogRowCopyWith<$Res> implements $CatalogRowCopyWith<$Res> {
  factory _$CatalogRowCopyWith(_CatalogRow value, $Res Function(_CatalogRow) _then) = __$CatalogRowCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String summary, String category, String version, CatalogForm? form, bool official
});




}
/// @nodoc
class __$CatalogRowCopyWithImpl<$Res>
    implements _$CatalogRowCopyWith<$Res> {
  __$CatalogRowCopyWithImpl(this._self, this._then);

  final _CatalogRow _self;
  final $Res Function(_CatalogRow) _then;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? summary = null,Object? category = null,Object? version = null,Object? form = freezed,Object? official = null,}) {
  return _then(_CatalogRow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,form: freezed == form ? _self.form : form // ignore: cast_nullable_to_non_nullable
as CatalogForm?,official: null == official ? _self.official : official // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
