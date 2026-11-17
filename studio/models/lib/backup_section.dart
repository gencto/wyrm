import 'package:wyrm_core/wyrm_core.dart';

/// A section of a backup (ADR 0048 §3.2 for a broker backup, §3.5 for a
/// link backup), by the broker's name (`SectionName` of `wyrm-admin`). The
/// broker refuses a name that is not here, and so does this client: what
/// is sealed and what is restored depends on it.
enum BackupSection implements WireName {
  control('control'),
  keys('keys'),
  dataflows('dataflows'),
  storage('storage'),
  history('history'),
  links('links'),
  packages('packages'),
  config('config'),
  settings('settings'),
  data('data'),
  package('package');

  const BackupSection(this.wire);

  @override
  final String wire;

  static BackupSection? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;

  /// The sections of a link backup, in the broker's order
  /// (`LINK_SECTIONS`).
  static const List<BackupSection> ofLink = [settings, data, package, history];

  /// Always in a backup: the broker's `control`, a link's `settings`.
  bool get always => this == control || this == settings;
}
