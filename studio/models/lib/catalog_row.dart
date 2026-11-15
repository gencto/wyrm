import 'package:freezed_annotation/freezed_annotation.dart';

import 'catalog_form.dart';

part 'catalog_row.freezed.dart';

/// One row of `attr.catalog` on `sys/links` (ADR 0043 §7): what the broker
/// says of one item of its `install` / `install_repo` choices. An empty
/// text is a field the broker left out; a null [form] too.
@freezed
abstract class CatalogRow with _$CatalogRow {
  const factory CatalogRow({
    /// `driver:<code>` or `package:<code>`.
    required String id,
    @Default('') String title,
    @Default('') String summary,
    @Default('') String category,
    @Default('') String version,
    CatalogForm? form,
    @Default(false) bool official,
  }) = _CatalogRow;
}
