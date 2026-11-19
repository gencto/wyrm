import 'package:wyrm_client/wyrm_client.dart';

// The leaves of `sys` whose live values the screens decode, by their wire
// names: a key is told apart once, here, and the reader switches over the
// enum.

/// A leaf of `sys/links/<id>` that Links reads live.
enum LinkLiveLeaf implements WireName {
  state('state'),
  restorePoints('restore_points');

  const LinkLiveLeaf(this.wire);

  @override
  final String wire;

  static LinkLiveLeaf? fromWire(String wire) =>
      values.where((l) => l.wire == wire).firstOrNull;
}

/// A leaf of `sys/history/<group>` that History reads live.
enum GroupLiveLeaf implements WireName {
  loggingType('logging_type'),
  interval('interval'),
  flush('buffer_flush_time');

  const GroupLiveLeaf(this.wire);

  @override
  final String wire;

  static GroupLiveLeaf? fromWire(String wire) =>
      values.where((l) => l.wire == wire).firstOrNull;
}
