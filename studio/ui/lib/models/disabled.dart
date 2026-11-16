import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../indicators/level_badge.dart';

/// Why a control is shown disabled (docs/studio.md §2 rule 8: shown, never
/// hidden); `ui` says it, as the control's tooltip or its line.
sealed class Disabled extends Equatable {
  const Disabled();

  /// The sentence.
  String get text;

  @override
  List<Object?> get props => [];
}

/// The user lacks [level] on [path] (the key under the site).
final class NeedsLevel extends Disabled {
  const NeedsLevel(this.level, this.path);

  final AccessLevel level;
  final String path;

  @override
  String get text => S.current.needsLevelOn(level.label, path);

  @override
  List<Object?> get props => [level, path];
}

/// The node has no action [action].
final class NoAction extends Disabled {
  const NoAction(this.action);

  final String action;

  @override
  String get text => S.current.noActionReason(action);

  @override
  List<Object?> get props => [action];
}

/// A control the broker or the node has nothing for yet.
final class NotThere extends Disabled {
  const NotThere(this.what);

  final Missing what;

  @override
  String get text => switch (what) {
    Missing.ping => S.current.noPingReason,
    Missing.profile => S.current.noProfileReason,
    Missing.edit => S.current.noEditReason,
    Missing.historyAction => S.current.noHistoryAction,
    Missing.readFlow => S.current.noReadFlow,
  };

  @override
  List<Object?> get props => [what];
}

/// What [NotThere] is missing.
enum Missing {
  /// The device has no `ping`.
  ping,

  /// The broker has no action to apply a profile yet.
  profile,

  /// A checked row has no `edit`.
  edit,

  /// The broker has no action to record points in history yet.
  historyAction,

  /// The user may not read the flow.
  readFlow,
}

/// Why a control of the flow editor is off: Deploy, the My blocks tab, an
/// item of a custom block's menu or of the canvas menu (docs/studio.md §2
/// rule 8: shown, never hidden).
enum FlowOffReason {
  /// The draft is not read yet.
  loading,

  /// Deploy inside a custom block: go back to the flow.
  deployInside,
  nothingToDeploy,

  /// The draft has problems.
  fixFirst,

  /// The broker has no custom blocks (the My blocks tab).
  noCustomBlocks,

  /// Inside a custom block: go back to the flow first.
  backFirst,
  notInLibrary,
  sameVersion,

  /// A save to, update from or removal from the library runs.
  libraryBusy,

  /// A custom block placed inside itself.
  insideItself,
  nothingSelected,

  /// The broker has no custom blocks (the canvas menu).
  needsBroker,
  nothingToUndo,
  nothingToRedo,
  notCustom,

  /// `Run` of a block: the broker has no `trigger` action.
  runNoBroker,

  /// `Run`: the flow is not deployed.
  runNotDeployed,

  /// `Run`: the draft differs from the deployed version.
  runDraft,

  /// `Run`: a block of a custom block opened from the palette.
  runNoInstance,

  /// `Run`: the block is disabled.
  runOff;

  String get label => switch (this) {
    loading => S.current.loading,
    deployInside => S.current.deployInside,
    nothingToDeploy => S.current.nothingToDeploy,
    fixFirst => S.current.fixFirst,
    noCustomBlocks => S.current.myBlocksOff,
    backFirst => S.current.mbBackFirst,
    notInLibrary => S.current.mbNotInLibrary,
    sameVersion => S.current.mbSameVersion,
    libraryBusy => S.current.mbLibraryBusy,
    insideItself => S.current.mbInsideItself,
    nothingSelected => S.current.fmNothingSelected,
    needsBroker => S.current.fmNeedsBroker,
    nothingToUndo => S.current.fmNothingToUndo,
    nothingToRedo => S.current.fmNothingToRedo,
    notCustom => S.current.fmNotCustom,
    runNoBroker => S.current.runNoBroker,
    runNotDeployed => S.current.runNotDeployed,
    runDraft => S.current.runDraft,
    runNoInstance => S.current.runNoInstance,
    runOff => S.current.runOff,
  };
}

/// A control of the flow editor off for [reason].
final class FlowOff extends Disabled {
  const FlowOff(this.reason);

  final FlowOffReason reason;

  @override
  String get text => reason.label;

  @override
  List<Object?> get props => [reason];
}

/// A custom block that cannot be deleted: [count] instances use it.
final class InUse extends Disabled {
  const InUse(this.count);

  final int count;

  @override
  String get text => S.current.mbInUse(count);

  @override
  List<Object?> get props => [count];
}
