import 'package:wyrm_core/wyrm_core.dart';

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
