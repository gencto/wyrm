import 'package:wyrm_core/wyrm_core.dart';

/// How the last update or rollback of a package ended (`result` of
/// `sys/packages/<name>/last_update`, ADR 0048 §1): its health check
/// runs, it ran, it was rolled back, or it failed.
enum UpdateResult implements WireName {
  checking('checking'),
  ok('ok'),
  rolledBack('rolled_back'),
  failed('failed'),

  /// A result this client does not know: the broker's own word is kept
  /// beside it (`UpdateReport.resultWord`) and shown as such.
  unknown('unknown');

  const UpdateResult(this.wire);

  @override
  final String wire;

  static UpdateResult? fromWire(String wire) =>
      values.where((r) => r.wire == wire).firstOrNull;
}
