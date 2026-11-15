import 'package:wyrm_core/wyrm_core.dart';

/// Where the broker's update of itself is (`sys/update_state`, ADR 0048
/// §2.4).
enum SelfUpdateState implements WireName {
  none('none'),
  staged('staged'),
  trial('trial'),
  confirmed('confirmed'),
  rolledBack('rolled_back');

  const SelfUpdateState(this.wire);

  @override
  final String wire;

  /// An update runs or ended: the dialog opens on what the broker says.
  bool get runs => this != none;

  static SelfUpdateState? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}

/// How the broker is updated (`sys/update_mode`, `updates.mode`): by
/// itself, or from outside (a container, a distribution package): it
/// cannot replace itself then.
enum SelfUpdateMode implements WireName {
  self('self'),
  external('external');

  const SelfUpdateMode(this.wire);

  @override
  final String wire;

  static SelfUpdateMode? fromWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
