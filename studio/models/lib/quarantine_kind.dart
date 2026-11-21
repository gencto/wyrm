import 'package:wyrm_core/wyrm_core.dart';

/// What waits under `sys/quarantine` (`attr.kind`): a link's certificate,
/// or a downstream broker asking for Authorize (ADR 0015). Names as in
/// `crates/wyrm-admin`. An entry answered under another kind is
/// `QuarantineEntry.notRead`: the decoder refuses it, and it is listed as
/// one that was not read.
enum QuarantineKind implements WireName {
  link('link'),
  broker('broker');

  const QuarantineKind(this.wire);

  @override
  final String wire;

  static QuarantineKind? fromWire(String wire) =>
      values.where((k) => k.wire == wire).firstOrNull;
}
