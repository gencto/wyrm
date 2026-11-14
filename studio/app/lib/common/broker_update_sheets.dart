import 'package:localization/localization.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/overlays/task_sheet.dart';

/// Which screen of a broker update the dialog shows.
enum BrokerUpdateStage { review, restarting, confirmed, rolledBack, external }

/// What the broker update dialog is built from (boards `BrokerUpdate*`,
/// spec `docs/design/specs/updates-backups.md` §3). The broker side is
/// ADR 0048 §2, which is not built: the names here are the ADR's.
final class BrokerUpdateData {
  const BrokerUpdateData({
    required this.site,
    required this.version,
    required this.latest,
    this.follow = false,
    this.mode = 'self',
    this.updateState = 'none',
    this.last = const {},
    this.connected = true,
    this.lostSeconds = 0,
    this.confirm = '',
    this.busy = false,
    this.reason,
  });

  final String site;

  /// `sys/version`: what runs now.
  final String version;

  /// `sys/latest`: the release the channel offers.
  final String latest;

  /// The dialog follows `update_state`, else it is the review.
  final bool follow;

  /// `updates.mode`: `self`, or `external` (a container, a distribution
  /// package): the broker cannot replace itself.
  final String mode;

  /// `sys/update_state`: `none`, `staged`, `trial`, `confirmed`,
  /// `rolled_back`.
  final String updateState;

  /// `sys/update_last`: `from`, `to`, `at`, `reason`, `down_s`,
  /// `links_back`, `links`, `back_s`, `rollback_until`, as texts.
  final Map<String, String> last;

  /// The gateway socket is up.
  final bool connected;

  /// How long the gateway has been lost.
  final int lostSeconds;

  /// What the user typed to confirm.
  final String confirm;
  final bool busy;
  final String? reason;

  BrokerUpdateStage get stage {
    if (mode == 'external') {
      return .external;
    }
    if (!follow) {
      return .review;
    }
    return switch (updateState) {
      'confirmed' when connected => .confirmed,
      'rolled_back' when connected => .rolledBack,
      _ => .restarting,
    };
  }

  String get from => last['from'] ?? version;
  String get to => last['to'] ?? latest;
}

/// The broker update dialog at its stage.
TaskSheetVm brokerUpdateSheet(BrokerUpdateData d) => switch (d.stage) {
  .review => _review(d),
  .restarting => _restarting(d),
  .confirmed => _confirmed(d),
  .rolledBack => _rolledBack(d),
  .external => _external(d),
};

TaskSheetVm _review(BrokerUpdateData d) {
  final l = S.current;
  final typed = d.confirm == d.site;
  return TaskSheetVm(
    title: l.bupTitle(d.site, d.latest),
    pill: '${d.version} → ${d.latest}',
    pillTone: .ember,
    sub: l.bupSub,
    blocks: [
      SheetLabel(l.bupChecked),
      // The broker checks these when the update starts and refuses it with
      // the one that failed; nothing changes before they pass.
      SheetCard(title: l.bupCheckSigned, detail: l.bupCheckSignedNote),
      SheetCard(title: l.bupCheckConfig, detail: l.bupCheckConfigNote),
      SheetCard(title: l.bupCheckRoom, detail: l.bupCheckRoomNote),
      SheetCard(
        tone: .warn,
        title: l.bupCheckSchema,
        detail: l.bupCheckSchemaNote(d.version),
      ),
      SheetCard(
        tone: .warn,
        title: l.bupCheckStandby,
        detail: l.bupCheckStandbyNote,
      ),
      SheetLabel(l.bupHow),
      SheetBullets(
        [
          l.bupStep1,
          l.bupStep2(d.version),
          l.bupStep3(d.latest),
          l.bupStep4(d.latest),
          l.bupStep5(d.version),
        ],
        numbered: true,
      ),
      SheetField(
        id: 'confirm',
        label: l.bupType(d.site),
        value: d.confirm,
        hint: d.site,
      ),
    ],
    note: d.reason ?? l.bupNeedsConfig,
    secondary: l.cancel,
    primary: l.bupDo,
    primaryEnabled: d.reason == null && typed,
    primaryReason: d.reason ?? (typed ? null : l.bupType(d.site)),
    busy: d.busy,
  );
}

String _clock(int seconds) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
}

TaskSheetVm _restarting(BrokerUpdateData d) {
  final l = S.current;
  // Before the restart the steps are the action's; after it, what
  // `update_state` says once the socket is back.
  final back = d.connected && d.updateState == 'trial';
  SheetStepState after(bool done, bool now) =>
      done ? .done : (now ? .now : .todo);
  return TaskSheetVm(
    title: l.bupUpdating(d.site),
    pill: l.bupPillRestarting,
    pillTone: .ember,
    sub: l.bupUpdatingSub,
    blocks: [
      SheetSpinner(
        title: l.bupRestarting(d.site, d.to),
        text: d.connected ? l.bupOnTrial : l.bupLost(_clock(d.lostSeconds)),
      ),
      SheetSteps([
        SheetStep(l.bupDonePreBackup, .done),
        SheetStep(l.bupDoneStaged(d.to), .done),
        SheetStep(
          l.bupDoneRestart(d.from, d.to),
          after(back, !d.connected),
        ),
        SheetStep(l.bupDoneBack, after(false, back)),
        SheetStep(l.bupDoneConfirmed, .todo),
      ]),
      SheetText(l.bupMeanwhile, small: true),
    ],
    note: l.bupClosing,
    secondary: l.bupHide,
    primary: l.bupReconnecting,
    primaryEnabled: false,
    busy: true,
  );
}

TaskSheetVm _confirmed(BrokerUpdateData d) {
  final l = S.current;
  String fact(String k) => d.last[k] ?? '—';
  return TaskSheetVm(
    title: l.bupUpdated(d.site),
    pill: d.to,
    pillTone: .good,
    blocks: [
      SheetBanner(
        title: l.bupRuns(d.site, d.to),
        text: l.bupRunsNote(d.from),
      ),
      SheetFacts([
        FactVm(label: l.bupFactVersion, value: '${d.from} → ${d.to}'),
        FactVm(
          label: l.bupFactDown,
          value: l.bupSeconds(fact('down_s')),
        ),
        FactVm(
          label: l.bupFactLinks,
          value: l.bupLinksBack(
            fact('links_back'),
            fact('links'),
            fact('back_s'),
          ),
        ),
        FactVm(
          label: l.bupFactRollBack,
          value: l.bupRollBackUntil(fact('rollback_until')),
        ),
        FactVm(label: l.bupFactAudit, value: 'update_start, update_confirmed'),
      ]),
    ],
    note: d.reason,
    secondary: l.updClose,
    primary: l.updRollBackTo(d.from),
    primaryQuiet: true,
    primaryEnabled: d.reason == null,
    primaryReason: d.reason,
    busy: d.busy,
  );
}

TaskSheetVm _rolledBack(BrokerUpdateData d) {
  final l = S.current;
  return TaskSheetVm(
    title: l.bupRolledBack,
    pill: d.from,
    pillTone: .warn,
    blocks: [
      SheetBanner(
        tone: .warn,
        title: l.bupBackOn(d.from),
        text: l.bupBackOnNote(d.to, d.from),
      ),
      SheetFacts([
        FactVm(label: l.bupFactTried, value: d.to),
        FactVm(label: l.bupFactReason, value: d.last['reason'] ?? '—'),
        FactVm(label: l.bupFactNow, value: d.from),
        FactVm(label: l.bupFactAudit, value: 'update_rollback'),
      ]),
    ],
    secondary: l.updClose,
    primary: l.bupOpenLog(d.to),
  );
}

TaskSheetVm _external(BrokerUpdateData d) {
  final l = S.current;
  return TaskSheetVm(
    title: l.bupTitle(d.site, d.latest),
    pill: l.bupPillContainer,
    blocks: [
      SheetText(l.bupExternal),
      SheetCode(
        'image: ghcr.io/gencto/wyrmd:${d.latest}\n'
        'docker compose pull wyrmd && docker compose up -d wyrmd',
      ),
      SheetText(l.bupExternalBackup),
    ],
    secondary: l.updClose,
    primary: l.bupMakeBackup,
    primaryEnabled: d.reason == null,
    primaryReason: d.reason,
  );
}
