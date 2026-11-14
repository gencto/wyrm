import '../../app_state.dart';
import '../../common/action.dart';

/// One answer of the backup dialog changes: a section or a link is ticked
/// or unticked, the history range, where the file goes, the file store,
/// the restore's mode and its two confirmations.
class SetBackupFormAction extends Action {
  SetBackupFormAction({
    this.toggle,
    this.toggleLink,
    this.historyDays,
    this.where,
    this.sendLink,
    this.sendConnection,
    this.sendPath,
    this.mode,
    this.replaceKeys,
    this.acceptRights,
  });

  /// The section to tick or untick. `control` (broker) and `settings`
  /// (link) are always in.
  final String? toggle;

  /// A link of the section `links` to tick or untick.
  final String? toggleLink;

  /// The last N days of history; 0 = all of it.
  final int? historyDays;

  /// `computer`, `store` or `broker`.
  final String? where;
  final String? sendLink;
  final String? sendConnection;
  final String? sendPath;

  /// `add` or `replace`.
  final String? mode;
  final bool? replaceKeys;
  final bool? acceptRights;

  @override
  AppState reduce() {
    var chosen = backups.chosen;
    if (toggle case final s? when s != 'control' && s != 'settings') {
      chosen = chosen.contains(s) ? chosen.remove(s) : chosen.add(s);
    }
    var off = backups.offLinks;
    if (toggleLink case final l?) {
      off = off.contains(l) ? off.remove(l) : off.add(l);
    }
    return state.copyWith.backups(
      chosen: chosen,
      offLinks: off,
      historyDays: switch (historyDays) {
        null => backups.historyDays,
        0 => null,
        final n => n,
      },
      where: where ?? backups.where,
      sendLink: sendLink ?? backups.sendLink,
      // Another link has other connections.
      sendConnection: sendLink != null && sendLink != backups.sendLink
          ? null
          : sendConnection ?? backups.sendConnection,
      sendPath: sendPath ?? backups.sendPath,
      mode: mode ?? backups.mode,
      replaceKeys: replaceKeys ?? backups.replaceKeys,
      acceptRights: acceptRights ?? backups.acceptRights,
    );
  }
}
