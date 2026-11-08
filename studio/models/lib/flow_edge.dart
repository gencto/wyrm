import 'package:freezed_annotation/freezed_annotation.dart';

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
}
