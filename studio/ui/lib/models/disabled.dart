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
