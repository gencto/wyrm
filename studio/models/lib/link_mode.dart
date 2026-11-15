import 'package:wyrm_core/wyrm_core.dart';

/// How a link runs (`attr.mode` of `sys/links/<id>`, the `mode` of
/// `install`): inside the broker, as its own process, as a WASM component,
/// or on another machine.
enum LinkMode implements WireName {
  embedded('embedded'),
  process('process'),
  wasm('wasm'),
  external('external');

  const LinkMode(this.wire);

  @override
  final String wire;

  static LinkMode? fromWire(String wire) =>
      values.where((m) => m.wire == wire).firstOrNull;
}
