import 'package:wyrm_core/wyrm_core.dart';

/// A link of a backup against this broker (`links` of the answer of
/// `restore_check`).
enum RestoreLinkState implements WireName {
  /// The broker has no link of this id.
  fresh('new'),

  /// The broker has one: a restore replaces it.
  exists('exists');

  const RestoreLinkState(this.wire);

  @override
  final String wire;

  static RestoreLinkState? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
