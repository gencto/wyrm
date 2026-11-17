// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogItem {

/// `driver:<name>` or `package:<name>`.
 String get id;/// The driver or package name the broker knows.
 String get code;/// The broker's title of it (`attr.catalog` row `title`), else its
/// code; empty when Studio words it ([titled]).
 String get name;/// The broker's one line of it (row `summary`); empty when it gave
/// none ([described] may then word it).
 String get description;/// The driver Studio words the title of: the broker gave none.
 KnownLink? get titled;/// The driver Studio words the one line of: the broker gave none.
 KnownLink? get described;/// A process package whose title does not say so: the card adds it
/// (both forms of one link may carry one title).
 bool get processForm;/// A short tag (`MB`, `PG`).
 String get tag;/// One of the manifest's categories, or the broker's own text.
 CatalogCategory get category;/// Built into wyrmd (`install`), else a repository package
/// (`install_repo`).
 bool get builtIn;/// How it can run, the first the default.
 IList<LinkMode> get modes;/// Links of it the broker already has.
 int get existing;/// What the card says of its version: `wyrmd 0.1.0` for a driver built
/// into the broker (its `sys/version`); null when the broker does not
/// say (a repository package of an old broker: `install_repo` lists
/// names only). A broker with `attr.catalog` on `sys/links` (ADR 0043
/// §7) gives a package the version of its index entry.
 String? get version;/// The broker says it is an official link (`attr.catalog` row
/// `official`, ADR 0043 §5): a built-in driver its manifest names, or a
/// package of the official index at the listed version. Never guessed
/// from a name.
 bool get official;
/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogItemCopyWith<CatalogItem> get copyWith => _$CatalogItemCopyWithImpl<CatalogItem>(this as CatalogItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogItem&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.titled, _this.titled) || other.titled == _this.titled)&&(identical(other.described, _this.described) || other.described == _this.described)&&(identical(other.processForm, _this.processForm) || other.processForm == _this.processForm)&&(identical(other.tag, _this.tag) || other.tag == _this.tag)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.builtIn, _this.builtIn) || other.builtIn == _this.builtIn)&&const DeepCollectionEquality().equals(other.modes, _this.modes)&&(identical(other.existing, _this.existing) || other.existing == _this.existing)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.official, _this.official) || other.official == _this.official));
}


@override
int get hashCode {
  final _this = this as CatalogItem;
  return Object.hash(runtimeType,_this.id,_this.code,_this.name,_this.description,_this.titled,_this.described,_this.processForm,_this.tag,_this.category,_this.builtIn,const DeepCollectionEquality().hash(_this.modes),_this.existing,_this.version,_this.official);
}

@override
String toString() {
  final _this = this as CatalogItem;
  return 'CatalogItem(id: ${_this.id}, code: ${_this.code}, name: ${_this.name}, description: ${_this.description}, titled: ${_this.titled}, described: ${_this.described}, processForm: ${_this.processForm}, tag: ${_this.tag}, category: ${_this.category}, builtIn: ${_this.builtIn}, modes: ${_this.modes}, existing: ${_this.existing}, version: ${_this.version}, official: ${_this.official})';
}


}

/// @nodoc
abstract mixin class $CatalogItemCopyWith<$Res>  {
  factory $CatalogItemCopyWith(CatalogItem value, $Res Function(CatalogItem) _then) = _$CatalogItemCopyWithImpl;
@useResult
$Res call({
 String id, String code, String name, String description, KnownLink? titled, KnownLink? described, bool processForm, String tag, CatalogCategory category, bool builtIn, IList<LinkMode> modes, int existing, String? version, bool official
});


$CatalogCategoryCopyWith<$Res> get category;

}
/// @nodoc
class _$CatalogItemCopyWithImpl<$Res>
    implements $CatalogItemCopyWith<$Res> {
  _$CatalogItemCopyWithImpl(this._self, this._then);

  final CatalogItem _self;
  final $Res Function(CatalogItem) _then;

/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? code = null,Object? name = null,Object? description = null,Object? titled = freezed,Object? described = freezed,Object? processForm = null,Object? tag = null,Object? category = null,Object? builtIn = null,Object? modes = null,Object? existing = null,Object? version = freezed,Object? official = null,}) {
  return _then(CatalogItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,titled: freezed == titled ? _self.titled : titled // ignore: cast_nullable_to_non_nullable
as KnownLink?,described: freezed == described ? _self.described : described // ignore: cast_nullable_to_non_nullable
as KnownLink?,processForm: null == processForm ? _self.processForm : processForm // ignore: cast_nullable_to_non_nullable
as bool,tag: null == tag ? _self.tag : tag // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as CatalogCategory,builtIn: null == builtIn ? _self.builtIn : builtIn // ignore: cast_nullable_to_non_nullable
as bool,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as IList<LinkMode>,existing: null == existing ? _self.existing : existing // ignore: cast_nullable_to_non_nullable
as int,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,official: null == official ? _self.official : official // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CatalogCategoryCopyWith<$Res> get category {
  
  return $CatalogCategoryCopyWith<$Res>(_self.category, (value) {
    return _then(_self.copyWith(category: value));
  });
}
}



/// @nodoc


class _CatalogItem implements CatalogItem {
  const _CatalogItem({required this.id, required this.code, this.name = '', this.description = '', this.titled, this.described, this.processForm = false, this.tag = '', this.category = const CatalogCategory.known(LinkCategory.equipment), this.builtIn = true, this.modes = const IListConst([]), this.existing = 0, this.version, this.official = false});
  

/// `driver:<name>` or `package:<name>`.
@override final  String id;
/// The driver or package name the broker knows.
@override final  String code;
/// The broker's title of it (`attr.catalog` row `title`), else its
/// code; empty when Studio words it ([titled]).
@override@JsonKey() final  String name;
/// The broker's one line of it (row `summary`); empty when it gave
/// none ([described] may then word it).
@override@JsonKey() final  String description;
/// The driver Studio words the title of: the broker gave none.
@override final  KnownLink? titled;
/// The driver Studio words the one line of: the broker gave none.
@override final  KnownLink? described;
/// A process package whose title does not say so: the card adds it
/// (both forms of one link may carry one title).
@override@JsonKey() final  bool processForm;
/// A short tag (`MB`, `PG`).
@override@JsonKey() final  String tag;
/// One of the manifest's categories, or the broker's own text.
@override@JsonKey() final  CatalogCategory category;
/// Built into wyrmd (`install`), else a repository package
/// (`install_repo`).
@override@JsonKey() final  bool builtIn;
/// How it can run, the first the default.
@override@JsonKey() final  IList<LinkMode> modes;
/// Links of it the broker already has.
@override@JsonKey() final  int existing;
/// What the card says of its version: `wyrmd 0.1.0` for a driver built
/// into the broker (its `sys/version`); null when the broker does not
/// say (a repository package of an old broker: `install_repo` lists
/// names only). A broker with `attr.catalog` on `sys/links` (ADR 0043
/// §7) gives a package the version of its index entry.
@override final  String? version;
/// The broker says it is an official link (`attr.catalog` row
/// `official`, ADR 0043 §5): a built-in driver its manifest names, or a
/// package of the official index at the listed version. Never guessed
/// from a name.
@override@JsonKey() final  bool official;

/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogItemCopyWith<_CatalogItem> get copyWith => __$CatalogItemCopyWithImpl<_CatalogItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogItem&&(identical(other.id, id) || other.id == id)&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.titled, titled) || other.titled == titled)&&(identical(other.described, described) || other.described == described)&&(identical(other.processForm, processForm) || other.processForm == processForm)&&(identical(other.tag, tag) || other.tag == tag)&&(identical(other.category, category) || other.category == category)&&(identical(other.builtIn, builtIn) || other.builtIn == builtIn)&&const DeepCollectionEquality().equals(other.modes, modes)&&(identical(other.existing, existing) || other.existing == existing)&&(identical(other.version, version) || other.version == version)&&(identical(other.official, official) || other.official == official));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,code,name,description,titled,described,processForm,tag,category,builtIn,const DeepCollectionEquality().hash(modes),existing,version,official);
}

@override
String toString() {
    return 'CatalogItem(id: $id, code: $code, name: $name, description: $description, titled: $titled, described: $described, processForm: $processForm, tag: $tag, category: $category, builtIn: $builtIn, modes: $modes, existing: $existing, version: $version, official: $official)';
}


}

/// @nodoc
abstract mixin class _$CatalogItemCopyWith<$Res> implements $CatalogItemCopyWith<$Res> {
  factory _$CatalogItemCopyWith(_CatalogItem value, $Res Function(_CatalogItem) _then) = __$CatalogItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String code, String name, String description, KnownLink? titled, KnownLink? described, bool processForm, String tag, CatalogCategory category, bool builtIn, IList<LinkMode> modes, int existing, String? version, bool official
});


@override $CatalogCategoryCopyWith<$Res> get category;

}
/// @nodoc
class __$CatalogItemCopyWithImpl<$Res>
    implements _$CatalogItemCopyWith<$Res> {
  __$CatalogItemCopyWithImpl(this._self, this._then);

  final _CatalogItem _self;
  final $Res Function(_CatalogItem) _then;

/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? code = null,Object? name = null,Object? description = null,Object? titled = freezed,Object? described = freezed,Object? processForm = null,Object? tag = null,Object? category = null,Object? builtIn = null,Object? modes = null,Object? existing = null,Object? version = freezed,Object? official = null,}) {
  return _then(_CatalogItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,titled: freezed == titled ? _self.titled : titled // ignore: cast_nullable_to_non_nullable
as KnownLink?,described: freezed == described ? _self.described : described // ignore: cast_nullable_to_non_nullable
as KnownLink?,processForm: null == processForm ? _self.processForm : processForm // ignore: cast_nullable_to_non_nullable
as bool,tag: null == tag ? _self.tag : tag // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as CatalogCategory,builtIn: null == builtIn ? _self.builtIn : builtIn // ignore: cast_nullable_to_non_nullable
as bool,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as IList<LinkMode>,existing: null == existing ? _self.existing : existing // ignore: cast_nullable_to_non_nullable
as int,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,official: null == official ? _self.official : official // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of CatalogItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CatalogCategoryCopyWith<$Res> get category {
  
  return $CatalogCategoryCopyWith<$Res>(_self.category, (value) {
    return _then(_self.copyWith(category: value));
  });
}
}

// dart format on
