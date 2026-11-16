import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../models/disabled.dart';

/// Why a control of the Assistant cannot be used now: the closed set of
/// reasons its buttons, tiles and box give, each worded here.
sealed class Blocked extends Equatable {
  const Blocked();

  /// The reason, as the control's tooltip and hint say it.
  String get text;

  @override
  List<Object?> get props => [];
}

/// The site has no agent link.
final class BlockedNoAgent extends Blocked {
  const BlockedNoAgent();

  @override
  String get text => S.current.noAgent;
}

/// A call of the same kind is on its way.
final class BlockedBusy extends Blocked {
  const BlockedBusy();

  @override
  String get text => '…';
}

/// The user lacks a level on a key, as the rights check found it.
final class BlockedLacks extends Blocked {
  const BlockedLacks(this.lack);

  final NeedsLevel lack;

  @override
  String get text => lack.text;

  @override
  List<Object?> get props => [lack];
}

/// The site on screen is not the gateway's own: it cannot sign for it.
final class BlockedOtherSite extends Blocked {
  const BlockedOtherSite(this.site);

  final String site;

  @override
  String get text => S.current.approveOtherSite(site);

  @override
  List<Object?> get props => [site];
}

/// The gateway cannot read a task's record (older than `doc`).
final class BlockedNoRecord extends Blocked {
  const BlockedNoRecord();

  @override
  String get text => S.current.approveReasonNote;
}

/// No step is ticked.
final class BlockedNoneTicked extends Blocked {
  const BlockedNoneTicked();

  @override
  String get text => S.current.approveNone;
}

/// The masked arguments of step [step] were not looked at.
final class BlockedReveal extends Blocked {
  const BlockedReveal(this.step);

  final int step;

  @override
  String get text => S.current.approveReveal(step);

  @override
  List<Object?> get props => [step];
}

/// The user may not follow the task up.
final class BlockedFollow extends Blocked {
  const BlockedFollow();

  @override
  String get text => S.current.followNeeds;
}

/// No option of the card is picked.
final class BlockedPickOne extends Blocked {
  const BlockedPickOne();

  @override
  String get text => S.current.choicesPickOne;
}

/// No row of *Same for more units?* is ticked.
final class BlockedNoRows extends Blocked {
  const BlockedNoRows();

  @override
  String get text => S.current.moreNone;
}

/// No site is on screen to pick a node of.
final class BlockedNoSite extends Blocked {
  const BlockedNoSite();

  @override
  String get text => S.current.addFromExplorerNone;
}

/// The ask holds as many `@` chips as the agent takes.
final class BlockedChipsFull extends Blocked {
  const BlockedChipsFull(this.max);

  final int max;

  @override
  String get text => S.current.pickKeyFull('$max');

  @override
  List<Object?> get props => [max];
}
