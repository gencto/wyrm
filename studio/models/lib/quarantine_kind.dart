import 'package:wyrm_core/wyrm_core.dart';

/// What waits under `sys/quarantine` (`attr.kind`): a link's certificate,
/// or a downstream broker asking for Authorize (ADR 0015).
enum QuarantineKind implements WireName {
  link('link'),
  broker('broker'),

  /// What waits there was answered in a form this Studio does not read:
  /// what it is, is not known. It is listed so that it does not vanish,
  /// and is never taken for a link or a broker. Never on the wire.
  notRead('');

  const QuarantineKind(this.wire);

  @override
  final String wire;

  static QuarantineKind? fromWire(String wire) =>
      values.where((k) => k != notRead && k.wire == wire).firstOrNull;
}
