import 'package:wyrm_core/wyrm_core.dart';

/// Where the making of a backup is (`sys/backups/<id>/status`).
enum BackupStatus implements WireName {
  /// No `status` has arrived yet.
  unknown(''),
  running('running'),
  done('done'),
  failed('failed');

  const BackupStatus(this.wire);

  @override
  final String wire;

  static BackupStatus? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}

/// Where the sending of a backup to a file store is
/// (`sys/backups/<id>/send_status`).
enum BackupSendStatus implements WireName {
  /// Never sent.
  none(''),
  sending('sending'),
  done('done'),
  failed('failed');

  const BackupSendStatus(this.wire);

  @override
  final String wire;

  static BackupSendStatus? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
