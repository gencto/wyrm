import 'package:localization/localization.dart';
import 'package:models/flow_summary.dart';
import 'package:ui/models/tone.dart';

/// A flow's state as Flows and Explorer show it: its tone, its word
/// (`v2 deployed`, `v3 · error`, `v1 stopped`, `not deployed`) and the
/// error, if any.
(Tone, String, String?) flowStateOf(FlowSummary f) => switch (f) {
  FlowSummary(problem: final p?) => (
    Tone.bad,
    S.current.flowError(f.version ?? 0),
    p,
  ),
  FlowSummary(running: true) => (
    Tone.good,
    S.current.flowDeployed(f.version ?? 0),
    null,
  ),
  FlowSummary(version: final v?) => (
    Tone.neutral,
    S.current.flowStopped(v),
    null,
  ),
  _ => (Tone.neutral, S.current.notDeployed, null),
};
