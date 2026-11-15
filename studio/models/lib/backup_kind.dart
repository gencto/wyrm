import 'package:wyrm_core/wyrm_core.dart';

/// What a backup of `sys/backups/<id>` holds (ADR 0048 §3.4, attribute
/// `kind`).
enum BackupKind implements WireName {
  /// The broker's sections.
  full('full'),

  /// One link: its settings and data (`attr.link`).
  link('link'),

  /// Taken by the broker before a package update.
  preUpdate('pre-update'),

  /// Taken by the broker before a restore.
  preRestore('pre-restore');

  const BackupKind(this.wire);

  @override
  final String wire;

  static BackupKind? fromWire(String wire) =>
      values.where((k) => k.wire == wire).firstOrNull;
}
