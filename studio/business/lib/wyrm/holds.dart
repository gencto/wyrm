/// Why a control of the Assistant cannot be used now, as `business`
/// decides it; the screen words it (`ui` `Blocked`).
sealed class Hold {
  const Hold();
}

/// The site has no agent link.
final class HoldNoAgent extends Hold {
  const HoldNoAgent();
}

/// A call of the same kind is on its way.
final class HoldBusy extends Hold {
  const HoldBusy();
}

/// The user lacks a level on a key ([needs]: what the rights check says).
final class HoldLacks extends Hold {
  const HoldLacks(this.needs);

  final String needs;
}

/// The site on screen is not the gateway's own: it cannot sign for it.
final class HoldOtherSite extends Hold {
  const HoldOtherSite(this.site);

  final String site;
}

/// The gateway cannot read a task's record (older than `doc`).
final class HoldNoRecord extends Hold {
  const HoldNoRecord();
}

/// No step is ticked.
final class HoldNoneTicked extends Hold {
  const HoldNoneTicked();
}

/// The masked arguments of step [step] were not looked at.
final class HoldReveal extends Hold {
  const HoldReveal(this.step);

  final int step;
}

/// The user may not follow the task up.
final class HoldFollow extends Hold {
  const HoldFollow();
}

/// No option of the card is picked.
final class HoldPickOne extends Hold {
  const HoldPickOne();
}

/// No row of *Same for more units?* is ticked.
final class HoldNoRows extends Hold {
  const HoldNoRows();
}

/// No site is on screen.
final class HoldNoSite extends Hold {
  const HoldNoSite();
}

/// The ask holds as many `@` chips as the agent takes ([max]).
final class HoldChipsFull extends Hold {
  const HoldChipsFull(this.max);

  final int max;
}

/// What the card of a plan that waits says beside Approve, as `business`
/// decides it, in this order: the gateway cannot read the record, the
/// site is another one, the last approval was refused, the record is not
/// read yet, else what Approve signs. The screen words it.
sealed class ApprovalNote {
  const ApprovalNote();
}

/// The gateway is older than `doc`: the plan cannot be shown.
final class ApprovalNoRecord extends ApprovalNote {
  const ApprovalNoRecord();
}

/// The task is on [site]: this gateway does not sign for it.
final class ApprovalOtherSite extends ApprovalNote {
  const ApprovalOtherSite(this.site);

  final String site;
}

/// The last approval was refused ([why]); the task still waits.
final class ApprovalRefused extends ApprovalNote {
  const ApprovalRefused(this.why);

  final String why;
}

/// The task waits; its record is not read yet.
final class ApprovalWaiting extends ApprovalNote {
  const ApprovalWaiting();
}

/// Approve signs one token per ticked step with the user's [role];
/// [byAgent] changes run with the agent's own key.
final class ApprovalSigns extends ApprovalNote {
  const ApprovalSigns({required this.role, required this.byAgent});

  final String role;
  final int byAgent;
}
