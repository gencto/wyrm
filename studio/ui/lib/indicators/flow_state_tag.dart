import 'package:localization/localization.dart';

import '../models/tone.dart';
import 'status_pill.dart';

/// A flow's state: its tone and words (`v2 deployed`, `v3 · error`, `v1
/// stopped`, `not deployed`).
enum FlowStateTag {
  error(Tone.bad),
  deployed(Tone.good),
  stopped(Tone.neutral),
  notDeployed(Tone.neutral),

  /// The flow's value is not one Studio reads: its state is not known.
  unreadable(Tone.warn);

  const FlowStateTag(this.tone);

  final Tone tone;

  String label(int? version) => switch (this) {
    error => S.current.flowError(version ?? 0),
    deployed => S.current.flowDeployed(version ?? 0),
    stopped => S.current.flowStopped(version ?? 0),
    notDeployed => S.current.notDeployed,
    unreadable => S.current.flowStateUnread,
  };

  StatusPillVm pill(int? version) =>
      StatusPillVm(label: label(version), tone: tone);
}
