import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
    required String name,
    @Default('') String description,

    /// A short tag (`MB`, `PG`).
    @Default('') String tag,

    /// `Equipment`, `History sync`, `File stores`, `Apps`.
    @Default('Equipment') String category,

    /// Built into wyrmd (`install`), else a repository package
    /// (`install_repo`).
    @Default(true) bool builtIn,

    /// How it can run: `embedded`, `process`, `external`, or `wasm`.
    @Default(IListConst([])) IList<String> modes,

    /// Links of it the broker already has.
    @Default(0) int existing,

    /// What the card says of its version: `wyrmd 0.1.0` for a driver built
    /// into the broker (its `sys/version`); null when the broker does not
    /// say (a repository package: `install_repo` lists names only).
    String? version,
  }) = _CatalogItem;
}
