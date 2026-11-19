import 'package:wyrm_core/wyrm_core.dart';

/// A category of the official list (ADR 0043: the `category` of
/// `links/official.json` and of an `attr.catalog` row), as the manifest
/// writes it. [packages] is Studio's own: a repository package the broker
/// names no category for. `ui` words each in the language on screen.
enum LinkCategory implements WireName {
  equipment('Equipment'),
  apps('Apps'),
  fileStores('File stores'),
  historySync('History sync'),
  messaging('Messaging'),
  test('Test'),
  packages('Packages');

  const LinkCategory(this.wire);

  @override
  final String wire;

  static LinkCategory? fromWire(String wire) =>
      values.where((c) => c.wire == wire).firstOrNull;
}
