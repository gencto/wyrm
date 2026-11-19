// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_category.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogCategory {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogCategory);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CatalogCategory()';
}


}

/// @nodoc
class $CatalogCategoryCopyWith<$Res>  {
$CatalogCategoryCopyWith(CatalogCategory _, $Res Function(CatalogCategory) __);
}



/// @nodoc


class CatalogCategoryKnown extends CatalogCategory {
  const CatalogCategoryKnown(this.category): super._();
  

 final  LinkCategory category;

/// Create a copy of CatalogCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogCategoryKnownCopyWith<CatalogCategoryKnown> get copyWith => _$CatalogCategoryKnownCopyWithImpl<CatalogCategoryKnown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogCategoryKnown&&(identical(other.category, category) || other.category == category));
}


@override
int get hashCode {
    return Object.hash(runtimeType,category);
}

@override
String toString() {
    return 'CatalogCategory.known(category: $category)';
}


}

/// @nodoc
abstract mixin class $CatalogCategoryKnownCopyWith<$Res> implements $CatalogCategoryCopyWith<$Res> {
  factory $CatalogCategoryKnownCopyWith(CatalogCategoryKnown value, $Res Function(CatalogCategoryKnown) _then) = _$CatalogCategoryKnownCopyWithImpl;
@useResult
$Res call({
 LinkCategory category
});




}
/// @nodoc
class _$CatalogCategoryKnownCopyWithImpl<$Res>
    implements $CatalogCategoryKnownCopyWith<$Res> {
  _$CatalogCategoryKnownCopyWithImpl(this._self, this._then);

  final CatalogCategoryKnown _self;
  final $Res Function(CatalogCategoryKnown) _then;

/// Create a copy of CatalogCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? category = null,}) {
  return _then(CatalogCategoryKnown(
null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as LinkCategory,
  ));
}


}

/// @nodoc


class CatalogCategoryNamed extends CatalogCategory {
  const CatalogCategoryNamed(this.name): super._();
  

 final  String name;

/// Create a copy of CatalogCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogCategoryNamedCopyWith<CatalogCategoryNamed> get copyWith => _$CatalogCategoryNamedCopyWithImpl<CatalogCategoryNamed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogCategoryNamed&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'CatalogCategory.named(name: $name)';
}


}

/// @nodoc
abstract mixin class $CatalogCategoryNamedCopyWith<$Res> implements $CatalogCategoryCopyWith<$Res> {
  factory $CatalogCategoryNamedCopyWith(CatalogCategoryNamed value, $Res Function(CatalogCategoryNamed) _then) = _$CatalogCategoryNamedCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$CatalogCategoryNamedCopyWithImpl<$Res>
    implements $CatalogCategoryNamedCopyWith<$Res> {
  _$CatalogCategoryNamedCopyWithImpl(this._self, this._then);

  final CatalogCategoryNamed _self;
  final $Res Function(CatalogCategoryNamed) _then;

/// Create a copy of CatalogCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(CatalogCategoryNamed(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
