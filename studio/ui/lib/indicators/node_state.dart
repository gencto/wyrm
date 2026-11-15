import 'package:localization/localization.dart';

import '../models/tone.dart';
import 'status_pill.dart';

/// The state of a link or a broker as Explorer draws it: a tree row's dot
/// (its word the tooltip) and the pill beside the node's name.
enum NodeState {
  connected(Tone.good),
  starting(Tone.warn),
  failed(Tone.bad),
  stopped(Tone.neutral),
  offline(Tone.bad);

  const NodeState(this.tone);

  final Tone tone;

  String get label => switch (this) {
    connected => S.current.stateConnected,
    starting => S.current.stateStarting,
    failed => S.current.stateFailed,
    stopped => S.current.stateStopped,
    offline => S.current.stateOffline,
  };

  /// A link's pill rings while it is on its way; a broker's is a dot.
  StatusPillVm pill({bool ring = true}) => StatusPillVm(
    label: label,
    tone: tone,
    mark: ring && tone == Tone.warn ? Mark.ring : Mark.dot,
  );
}

/// How a link runs, as the tree's chip names it.
enum LinkModeTag {
  embedded,
  process,
  wasm,
  external;

  String get label => switch (this) {
    embedded => S.current.modeEmbedded,
    process => S.current.modeProcess,
    wasm => S.current.modeWasm,
    external => S.current.modeExternal,
  };
}
