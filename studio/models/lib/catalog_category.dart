import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_category.dart';

part 'catalog_category.freezed.dart';

/// The category of an item of the official list: one of the manifest's
/// own ([LinkCategory], worded by `ui`), or the text a broker's
/// `attr.catalog` row gives that is none of them (shown as it came).
@freezed
sealed class CatalogCategory with _$CatalogCategory {
  const factory CatalogCategory.known(LinkCategory category) =
      CatalogCategoryKnown;

  const factory CatalogCategory.named(String name) = CatalogCategoryNamed;

  const CatalogCategory._();

  /// The category a row's [text] names.
  factory CatalogCategory.of(String text) =>
      switch (LinkCategory.fromWire(text)) {
        final c? => CatalogCategory.known(c),
        null => CatalogCategory.named(text),
      };
}
