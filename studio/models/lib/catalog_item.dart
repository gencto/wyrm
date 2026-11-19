import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'catalog_category.dart';
import 'known_link.dart';
import 'link_category.dart';
import 'link_mode.dart';

part 'catalog_item.freezed.dart';

/// One entry of Add a link's official list: a driver built into the broker
/// or a package of its repository.
@freezed
abstract class CatalogItem with _$CatalogItem {
  const factory CatalogItem({
    /// `driver:<name>` or `package:<name>`.
    required String id,

    /// The driver or package name the broker knows.
    required String code,

    /// The broker's title of it (`attr.catalog` row `title`), else its
    /// code; empty when Studio words it ([titled]).
    @Default('') String name,

    /// The broker's one line of it (row `summary`); empty when it gave
    /// none ([described] may then word it).
    @Default('') String description,

    /// The driver Studio words the title of: the broker gave none.
    KnownLink? titled,

    /// The driver Studio words the one line of: the broker gave none.
    KnownLink? described,

    /// A process package whose title does not say so: the card adds it
    /// (both forms of one link may carry one title).
    @Default(false) bool processForm,

    /// A short tag (`MB`, `PG`).
    @Default('') String tag,

    /// One of the manifest's categories, or the broker's own text.
    @Default(CatalogCategory.known(LinkCategory.equipment))
    CatalogCategory category,

    /// Built into wyrmd (`install`), else a repository package
    /// (`install_repo`).
    @Default(true) bool builtIn,

    /// How it can run, the first the default.
    @Default(IListConst([])) IList<LinkMode> modes,

    /// Links of it the broker already has.
    @Default(0) int existing,

    /// What the card says of its version: `wyrmd 0.1.0` for a driver built
    /// into the broker (its `sys/version`); null when the broker does not
    /// say (a repository package of an old broker: `install_repo` lists
    /// names only). A broker with `attr.catalog` on `sys/links` (ADR 0043
    /// §7) gives a package the version of its index entry.
    String? version,

    /// The broker says it is an official link (`attr.catalog` row
    /// `official`, ADR 0043 §5): a built-in driver its manifest names, or a
    /// package of the official index at the listed version. Never guessed
    /// from a name.
    @Default(false) bool official,
  }) = _CatalogItem;
}
