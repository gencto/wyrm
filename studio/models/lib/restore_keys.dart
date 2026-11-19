import 'package:wyrm_core/wyrm_core.dart';

/// How the keys of a backup compare with this broker's (`keys` of the
/// answer of `restore_check`, ADR 0048 §3.6).
enum RestoreKeys implements WireName {
  /// The file holds no keys.
  none('none'),

  /// Every key file is this broker's.
  same('same'),

  /// This broker's CA, other key files.
  differ('differ'),

  /// Another CA.
  other('other');

  const RestoreKeys(this.wire);

  @override
  final String wire;

  static RestoreKeys? fromWire(String wire) =>
      values.where((k) => k.wire == wire).firstOrNull;

  /// The keys of the file are not this broker's.
  bool get foreign => this == differ || this == other;
}
