import 'package:wyrm_core/wyrm_core.dart';

/// Where a link was set up (`attr.origin` of `sys/links/<id>`): in
/// `wyrmd.json5`, or installed or admitted while the broker runs.
enum LinkOrigin implements WireName {
  config('config'),
  runtime('runtime');

  const LinkOrigin(this.wire);

  @override
  final String wire;

  static LinkOrigin? fromWire(String wire) =>
      values.where((o) => o.wire == wire).firstOrNull;
}
