import 'package:wyrm_core/wyrm_core.dart';

/// How a staged restore ended, as the start that applied it wrote in the
/// audit (`op` of a record of `sys/audit`, ADR 0048 §3.6).
enum RestoreEnd implements WireName {
  applied('restore_applied'),

  /// The broker put the state before the restore back.
  failed('restore_failed');

  const RestoreEnd(this.wire);

  @override
  final String wire;

  static RestoreEnd? fromWire(String wire) =>
      values.where((e) => e.wire == wire).firstOrNull;
}
