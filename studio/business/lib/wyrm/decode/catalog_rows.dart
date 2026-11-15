import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

const _shape = 'catalog row';

/// What form an item of the official list takes (`attr.catalog` row
/// `form`, ADR 0043 §7): a driver built into wyrmd, a process package or a
/// WASM package.
enum CatalogForm implements WireName {
  builtin('builtin'),
  process('process'),
  wasm('wasm');

  const CatalogForm(this.wire);

  @override
  final String wire;

  static CatalogForm? fromWire(String wire) =>
      values.where((f) => f.wire == wire).firstOrNull;
}

/// One row of `attr.catalog` on `sys/links` (ADR 0043 §7): what the broker
/// says of one item of its `install` / `install_repo` choices. An empty
/// text is a field the broker left out; a null `form` too.
typedef CatalogRow = ({
  String title,
  String summary,
  String category,
  String version,
  CatalogForm? form,
  bool official,
});

/// The rows of `attr.catalog` by `id` (`driver:<code>` / `package:<code>`);
/// null when the broker sends none (built before ADR 0043). A row that is
/// not one is left out **and logged** with its field.
Map<String, CatalogRow>? catalogRowsOf(Map<String, Value>? attr) {
  final rows = attr?['catalog'];
  if (rows is! VArray) {
    return null;
  }
  return {
    for (final r in rows.v)
      if (catalogRowOf(r).orWarn('attr.catalog') case (final id, final row))
        id: row,
  };
}

/// One row of `attr.catalog`: its `id` and what it says; a row without an
/// `id` or with a field of another type is [Invalid].
Decoded<(String, CatalogRow)> catalogRowOf(Value r) {
  if (r is! VMap) {
    return const Invalid(_shape, '', 'not a map');
  }
  String? textAt(String k) => switch (r.v[k]) {
    null || VNull() => '',
    VStr(:final v) => v.trim(),
    _ => null,
  };
  final id = textAt('id');
  if (id == null || id.isEmpty) {
    return const Invalid(_shape, 'id', 'missing');
  }
  final official = switch (r.v['official']) {
    null || VNull() => false,
    VBool(:final v) => v,
    _ => null,
  };
  if (official == null) {
    return const Invalid(_shape, 'official', 'not a bool');
  }
  final form = textAt('form');
  final title = textAt('title');
  final summary = textAt('summary');
  final category = textAt('category');
  final version = textAt('version');
  for (final (field, value) in [
    ('title', title),
    ('summary', summary),
    ('category', category),
    ('version', version),
    ('form', form),
  ]) {
    if (value == null) {
      return Invalid(_shape, field, 'not a text');
    }
  }
  return Valid((
    id,
    (
      title: title!,
      summary: summary!,
      category: category!,
      version: version!,
      form: form!.isEmpty ? null : CatalogForm.fromWire(form),
      official: official,
    ),
  ));
}
