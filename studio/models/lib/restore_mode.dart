import 'package:wyrm_core/wyrm_core.dart';

import 'backup_section.dart';

/// How `restore_apply` restores (ADR 0048 §3.6, `RestoreMode` of
/// `wyrm-admin`).
enum RestoreMode implements WireName {
  /// Live: what does not exist yet.
  add('add'),

  /// Staged for the next start: the sections in place of this broker's.
  replace('replace');

  const RestoreMode(this.wire);

  @override
  final String wire;

  static RestoreMode? fromWire(String wire) =>
      values.where((m) => m.wire == wire).firstOrNull;

  /// The sections this mode restores, in the broker's order (`ADDABLE`,
  /// `REPLACEABLE`).
  List<BackupSection> get sections => switch (this) {
    add => const [BackupSection.links, BackupSection.storage],
    replace => const [
      BackupSection.control,
      BackupSection.keys,
      BackupSection.dataflows,
      BackupSection.storage,
      BackupSection.history,
      BackupSection.links,
      BackupSection.packages,
    ],
  };
}
