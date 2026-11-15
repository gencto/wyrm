import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_summary.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm, Status;

import '../decode/flow_val.dart';
import '../mappers/flow_mapper.dart';

/// Where the values the blocks show come from.
enum ValuesFrom { preview, deployed }

/// The inspector with nothing selected (spec §6, proposed): the flow.
final class FlowSummaryView extends Equatable {
  const FlowSummaryView({
    required this.name,
    required this.version,
    this.deployedBy,
    this.deployedAt,
    this.mayWrite,
    this.values,
    this.liveRefused = false,
    this.reads = const IListConst([]),
    this.writes = const IListConst([]),
    this.previewProblem,
    this.problems = const IListConst([]),
  });

  /// The flow's id; null: a new flow with no name yet.
  final String? name;

  /// Its deployed version; 0: not deployed.
  final int version;

  /// Who deployed it, and when (the time of its live `~val`; null when it
  /// is not watched).
  final String? deployedBy;
  final DateTime? deployedAt;

  /// The most it may write (`permissions.maxperm`).
  final Perm? mayWrite;

  /// Where the values come from; null: none are shown.
  final ValuesFrom? values;

  /// The watch or the preview was refused for a lack of rights.
  final bool liveRefused;

  /// The keys it reads and writes, relative to the site.
  final IList<String> reads;
  final IList<String> writes;

  /// The broker's compiler refused the draft's preview.
  final FlowProblem? previewProblem;

  /// The problems of the last validation.
  final IList<FlowProblem> problems;

  @override
  List<Object?> get props => [
    name,
    version,
    deployedBy,
    deployedAt,
    mayWrite,
    values,
    liveRefused,
    reads,
    writes,
    previewProblem,
    problems,
  ];
}

/// The summary of flow [id] ([d] the flow itself, every inside view folded
/// back): [own] its live `~val`, [known] its row of the Flows list.
FlowSummaryView summaryViewOf(
  String id,
  FlowDraft? d, {
  required int version,
  required LiveValue? own,
  required FlowSummary? known,
  required bool deployed,
  required bool previewing,
  required Status? watchRefused,
  required Status? previewOff,
  required FlowProblem? previewError,
  required IList<FlowProblem> problems,
}) {
  final val = flowValOf(own?.value).orWarn('flow $id');
  final by = val?.deployedBy ?? known?.deployedBy;
  final keys = d == null ? null : flowKeysOf(d);
  return FlowSummaryView(
    name: id.isEmpty ? null : id,
    version: version,
    deployedBy: by,
    deployedAt: by == null ? null : own?.time,
    mayWrite: d?.permissions?.maxperm,
    values: d != null && (previewing || deployed)
        ? (previewing ? ValuesFrom.preview : ValuesFrom.deployed)
        : null,
    liveRefused:
        watchRefused == Status.permissionDenied ||
        previewOff == Status.permissionDenied,
    reads: (keys?.reads ?? const <String>[]).lock,
    writes: (keys?.writes ?? const <String>[]).lock,
    previewProblem: previewing ? previewError : null,
    problems: problems,
  );
}
