import 'package:wyrm_core/wyrm_core.dart';

/// How the secrets of a backup are sealed (`attr.sealed`, ADR 0048 §3.2).
enum BackupSealed implements WireName {
  none('none'),
  passphrase('passphrase'),
  broker('broker');

  const BackupSealed(this.wire);

  @override
  final String wire;

  static BackupSealed? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
