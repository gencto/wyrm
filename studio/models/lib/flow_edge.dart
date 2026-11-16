import 'package:freezed_annotation/freezed_annotation.dart';

import 'port_end.dart';

part 'flow_edge.freezed.dart';

/// One edge of a flow: `<from>.<fromPort>` → `<to>.<toPort>`.
@freezed
abstract class FlowEdge with _$FlowEdge {
  const factory FlowEdge({
    required String from,
    required String fromPort,
    required String to,
    required String toPort,
  }) = _FlowEdge;

  const FlowEdge._();

  /// A wire from [from] to [to].
  factory FlowEdge.between(PortEnd from, PortEnd to) => FlowEdge(
    from: from.block,
    fromPort: from.port,
    to: to.block,
    toPort: to.port,
  );

  /// Where it starts: an output.
  PortEnd get source => PortEnd(from, fromPort);

  /// Where it ends: an input.
  PortEnd get target => PortEnd(to, toPort);
}
