import 'package:models/flow_summary.dart';

/// A flow's `~val` as a live sample hands it (`{state, error, version,
/// deployed_by, since}` as plain Dart) read as a [FlowSummary], the way
/// `RetrieveFlowsAction` reads it: state 0 runs, 2 is an error, no state
/// is a draft never deployed.
FlowSummary flowSummaryOfValue(
  String id,
  Object? value, {
  String? description,
}) {
  final v = value is Map<String, Object?> ? value : const <String, Object?>{};
  int? whole(Object? x) => switch (x) {
    final int i => i,
    final double d when d == d.truncateToDouble() => d.toInt(),
    _ => null,
  };
  final state = whole(v['state']);
  return FlowSummary(
    id: id,
    version: whole(v['version']),
    deployedBy: switch (v['deployed_by']) {
      final String s when s.isNotEmpty => s,
      _ => null,
    },
    problem: state == 2
        ? switch (v['error']) {
            final String e when e.isNotEmpty => e,
            _ => 'error',
          }
        : null,
    draft: state == null,
    description: description,
    running: state == 0,
  );
}
