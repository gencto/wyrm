import 'package:localization/localization.dart';

import '../models/tone.dart';
import 'quality_mark.dart';

/// The mark beside a value: its quality (the wire's word), or why it has
/// none. [vm] words it, with the time it was read when known.
enum SampleMark {
  good(Tone.good, Mark.dot),
  uncertain(Tone.warn, Mark.ring),
  bad(Tone.bad, Mark.dot),

  /// No value read yet.
  none(Tone.neutral, Mark.ring),

  /// Offline: the value held is from before.
  stale(Tone.neutral, Mark.dashed),

  /// Staged to be added, not applied yet.
  notApplied(Tone.neutral, Mark.ring);

  const SampleMark(this.tone, this.mark);

  final Tone tone;
  final Mark mark;

  String get label => switch (this) {
    good => S.current.qualityGood,
    uncertain => S.current.qualityUncertain,
    bad => S.current.qualityBad,
    none => S.current.noValue,
    stale => S.current.stale,
    notApplied => S.current.notApplied,
  };

  /// The mark, with [at] (when the value was read) after a quality.
  QualityMarkVm vm({DateTime? at}) => QualityMarkVm(
    label: switch ((this, at)) {
      (good || uncertain || bad, final t?) =>
        '$label · ${Formats.clockSeconds(t)}',
      _ => label,
    },
    tone: tone,
    mark: mark,
  );
}
