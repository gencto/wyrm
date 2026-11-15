import 'package:wyrm_core/wyrm_core.dart';

/// What a package runs (`attr.kind` of `sys/packages/<name>`): a process
/// per link, or a WASM component in the broker (hot start on update).
enum PackageKind implements WireName {
  process('process'),
  wasm('wasm');

  const PackageKind(this.wire);

  @override
  final String wire;

  static PackageKind? fromWire(String wire) =>
      values.where((k) => k.wire == wire).firstOrNull;
}
