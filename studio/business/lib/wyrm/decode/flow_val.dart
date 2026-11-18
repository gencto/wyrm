import 'package:models/flow_summary.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'decoded.dart';
import 'fields.dart';

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

/// [value] (a flow's `~val` as JSON) read. No value is an empty one (a
/// draft never deployed). A value that is no map, or a field of another
/// type, is [Invalid] with the field: a flow whose state cannot be read is
/// never taken for a draft.
Decoded<FlowVal> flowValOf(Object? value) {
  if (value == null) {
    return const Valid(FlowVal());
  }
  if (value is! Map<String, Object?>) {
    return const Invalid('flow value', '', 'not a map');
  }
  int? whole(String field) => switch (value[field]) {
    null => null,
    final int i => i,
    final double d when d == d.truncateToDouble() => d.toInt(),
    _ => throw BadField(field, 'not a whole number'),
  };
  String? text(String field) => switch (value[field]) {
    null || '' => null,
    final String s => s,
    _ => throw BadField(field, 'not a text'),
  };
  return decoding(
    'flow value',
    () => FlowVal(
      state: whole('state'),
      version: whole('version'),
      error: text('error'),
      deployedBy: text('deployed_by'),
    ),
  );
}

/// [value] (a flow's `~val` as it is read from the wire) read, as
/// [flowValOf] reads a live one.
Decoded<FlowVal> flowValOfWire(Value? value) => flowValOf(toDart(value));

/// The summary of flow [id] from its `~val` as [read]. A value Studio
/// cannot read gives a summary that says so ([FlowSummary.unreadable]):
/// the flow is listed, and is neither a draft nor running. Nothing is
/// recorded here (a selector calls this on every rebuild): the caller
/// that received the value records it once ([Decoded.record]).
FlowSummary flowSummaryOf(
  String id,
  Decoded<FlowVal> read, {
  String? description,
}) => switch (read) {
  Valid(:final value) => flowSummaryOfVal(id, value, description: description),
  Invalid() => FlowSummary(id: id, description: description, unreadable: true),
};

/// [shown] (a flow's row as it was last read) under its live `~val` as
/// [read]. A value Studio reads gives the row its state, error, deployer
/// and version (the row's version when the value names none), and the
/// row is readable again. A value it cannot read leaves the last version
/// and deployer read and says the state is not known: the flow is then
/// neither running, nor stopped, nor a draft.
FlowSummary flowUnderLive(FlowSummary shown, Decoded<FlowVal> read) =>
    switch (read) {
      Valid(:final value) => switch (flowSummaryOfVal(shown.id, value)) {
        final l => shown.copyWith(
          version: l.version ?? shown.version,
          deployedBy: l.deployedBy,
          problem: l.problem,
          draft: l.draft,
          running: l.running,
          unreadable: false,
        ),
      },
      Invalid() => shown.copyWith(
        problem: null,
        draft: false,
        running: false,
        unreadable: true,
      ),
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
