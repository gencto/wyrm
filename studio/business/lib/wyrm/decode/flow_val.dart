import 'package:models/flow_summary.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'decoded.dart';

/// A flow's own `~val` (`dataflows/<id>`, spec 06): `{state, error,
/// version, deployed_by, since}`, as a live sample hands it (JSON). State
/// 0 runs, 2 is an error; no state is a draft never deployed.
final class FlowVal {
  const FlowVal({this.state, this.error, this.version, this.deployedBy});

  final int? state;
  final String? error;
  final int? version;
  final String? deployedBy;

  @override
  bool operator ==(Object other) =>
      other is FlowVal &&
      other.state == state &&
      other.error == error &&
      other.version == version &&
      other.deployedBy == deployedBy;

  @override
  int get hashCode => Object.hash(state, error, version, deployedBy);
}

/// [value] (a flow's `~val` as JSON) read. No value is an empty one;
/// [Invalid] when it is no map. A field of another kind is left out (the
/// summary then says nothing of it).
Decoded<FlowVal> flowValOf(Object? value) => switch (value) {
  null => const Valid(FlowVal()),
  final Map<String, Object?> v => Valid(
    FlowVal(
      state: _whole(v['state']),
      version: _whole(v['version']),
      error: switch (v['error']) {
        final String e when e.isNotEmpty => e,
        _ => null,
      },
      deployedBy: switch (v['deployed_by']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
    ),
  ),
  _ => const Invalid('flow value', '', 'not a map'),
};

/// [value] (a flow's `~val` as it is read from the wire) read, as
/// [flowValOf] reads a live one.
Decoded<FlowVal> flowValOfWire(Value? value) => flowValOf(toDart(value));

int? _whole(Object? x) => switch (x) {
  final int i => i,
  final double d when d == d.truncateToDouble() => d.toInt(),
  _ => null,
};

/// The summary of flow [id] its `~val` [v] gives.
FlowSummary flowSummaryOfVal(String id, FlowVal v, {String? description}) =>
    FlowSummary(
      id: id,
      version: v.version,
      deployedBy: v.deployedBy,
      problem: v.state == 2 ? (v.error ?? 'error') : null,
      draft: v.state == null,
      description: description,
      running: v.state == 0,
    );
