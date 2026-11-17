import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/apply_restore_action.dart';
import 'package:business/redux/backups/actions/back_up_action.dart';
import 'package:business/redux/backups/actions/cancel_download_action.dart';
import 'package:business/redux/backups/actions/change_backup_form_action.dart';
import 'package:business/redux/backups/actions/check_restore_action.dart';
import 'package:business/redux/backups/actions/close_backup_action.dart';
import 'package:business/redux/backups/actions/create_backup_action.dart';
import 'package:business/redux/backups/actions/estimate_backup_action.dart';
import 'package:business/redux/backups/actions/open_backup_action.dart';
import 'package:business/redux/backups/actions/restore_action.dart';
import 'package:business/redux/backups/actions/retrieve_backups_action.dart';
import 'package:business/redux/backups/actions/send_backup_action.dart';
import 'package:business/redux/backups/actions/set_backup_form_action.dart';
import 'package:business/redux/backups/actions/upload_restore_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:ui/overlays/backup_data.dart';
import 'package:ui/overlays/backup_sheet.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../common/app_store.dart';
import '../common/backup_file_actions.dart';
import '../mappers/backup_mappers.dart';
import '../mappers/link_install_mappers.dart';
import '../mappers/rights_mappers.dart';
import '../navigation/leave_on_log_out_action.dart';

/// The selectors over a state, for a dialog's converter.
class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

/// The backup [id] of [state] with its live values, or null.
BackupJob? backupJobIn(AppState state, String? id) =>
    id == null ? null : _Sel(state).backupJob(id);

/// The session reaches the viewed site through an upstream broker: the
/// broker then refuses `keys`, a passphrase and a restore that replaces.
bool viaUpstreamIn(AppState state) {
  final s = _Sel(state);
  return s.site.viewed != s.site.name;
}

/// Opens the backup dialog (boards `Backup*`, `LinkBackup`): of the broker,
/// of one [link], of a kept backup ([job]: its progress or its download,
/// send and remove), or the [restore] of a file.
///
/// The passphrase lives in the dialog's own state only: it is handed to
/// the action that needs it and is in no store state, log or error text.
Future<void> showBackupDialog(
  BuildContext context, {
  String? link,
  String? job,
  bool restore = false,
}) async {
  final store = AppStore.of(context);
  // The attributes of sys/backups decide what the dialog offers.
  await store.dispatchAndWait(RetrieveBackupsAction());
  if (!context.mounted || store.state.backups.sections.isEmpty) {
    // A broker without `sys/backups`: the callers lock their buttons with
    // the reason, so this is only a broker that lost it meanwhile.
    return;
  }
  store.dispatchSync(OpenBackupAction(link: link, job: job, restore: restore));
  // A broker backup shows the size of each section, read while the dialog
  // is open. The dialog is closed in the store as soon as it closes: an
  // estimate that ends later is dropped (it was read for another opening),
  // and it is awaited only after that.
  final estimate = link == null && job == null && !restore
      ? store.dispatchAndWait(EstimateBackupAction())
      : null;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupDialog(store: store),
  );
  await store.dispatchAndWait(CloseBackupAction());
  await estimate;
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.store});

  final Store<AppState> store;

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  /// Typed here, sent as an action argument, kept nowhere else.
  var _passphrase = '';

  /// The stage last drawn: the passphrase is forgotten when it moves on.
  late BackupStage? _stage = _store.state.backups.stage;

  Store<AppState> get _store => widget.store;

  late final _watch = ['${_Sel(_store.state).site.root}/sys/backups/*/*'];

  @override
  void initState() {
    super.initState();
    _store.dispatchSync(WatchKeysAction(_watch));
  }

  @override
  void dispose() {
    _store.dispatchSync(UnwatchKeysAction(_watch));
    super.dispose();
  }

  BackupFormData _form(AppState state) {
    final s = _Sel(state);
    final b = s.backups;
    final link = b.link;
    final info = link == null ? null : s.links.table[link];
    return BackupFormData(
      site: s.site.viewed ?? '',
      link: link,
      linkMode: info?.mode.ui,
      linkDriver: info?.driver,
      sections: [
        if (link == null)
          for (final s in b.sections) s.part
        else
          for (final s in BackupSection.ofLink)
            // The broker refuses `package` for a built-in driver.
            if (s != BackupSection.package ||
                (info?.driver.startsWith('pkg:') ?? false))
              s.part,
      ],
      chosen: {for (final s in b.chosen) s.part},
      estimate: {
        for (final MapEntry(:key, :value) in b.estimate.entries)
          key.part: value,
      },
      historyDays: b.historyDays,
      linkIds: s.links.view.unlock,
      offLinks: b.offLinks.unlock,
      exportSecrets: b.exportSecrets,
      viaUpstream: viaUpstreamIn(state),
      passphraseLength: _passphrase.length,
      where: b.where.target,
      sendLinks: [for (final l in b.sendLinks) l.target],
      sendLink: b.sendLink,
      connections: b.connections.unlock,
      sendConnection: b.sendConnection,
      sendPath: b.sendPath,
      keepDays: b.keepDays,
      reason: s.site
          .lacks(
            Perm.config,
            link == null
                ? '${s.site.root}/sys/backups'
                : '${s.site.root}/sys/links/$link',
          )
          ?.disabled,
      busy: state.wait.isWaitingForType<CreateBackupAction>(),
    );
  }

  BackupJobData? _job(AppState state, BackupJob? j) {
    final s = _Sel(state);
    final b = s.backups;
    return j == null
        ? null
        : BackupJobData(
            job: j.facts,
            site: s.site.viewed ?? '',
            where: b.where.target,
            sendLinks: [for (final l in b.sendLinks) l.target],
            sendLink: b.sendLink,
            connections: b.connections.unlock,
            sendConnection: b.sendConnection,
            sendPath: b.sendPath,
            keepDays: b.keepDays,
            downloading: b.downloading == j.id,
            downloaded: b.downloaded,
            savedTo: b.saved[j.id],
            sending: state.wait.isWaitingForType<SendBackupAction>(),
            reason: s.site
                .lacks(Perm.config, '${s.site.root}/sys/backups')
                ?.disabled,
          );
  }

  RestoreData _restore(AppState state, RestoreView view) {
    final s = _Sel(state);
    final b = s.backups;
    return RestoreData(
      site: s.site.viewed ?? '',
      fileName: b.uploadName,
      size: b.uploadSize,
      uploaded: b.uploaded,
      uploading: state.wait.isWaitingForType<UploadRestoreAction>(),
      hasUpload: b.upload != null,
      check: b.check?.data,
      chosen: {for (final s in b.chosen) s.part},
      mode: b.mode.how,
      modeTakes: {for (final s in b.mode.sections) s.part},
      replaceKeys: b.replaceKeys,
      acceptRights: b.acceptRights,
      exportSecrets: b.exportSecrets,
      viaUpstream: viaUpstreamIn(state),
      passphraseLength: _passphrase.length,
      busy:
          state.wait.isWaitingForType<CheckRestoreAction>() ||
          state.wait.isWaitingForType<ApplyRestoreAction>(),
      view: view,
      staged: [for (final s in b.staged) s.part],
      result: b.result,
      reason: s.site.lacks(Perm.config, '${s.site.root}/sys/backups')?.disabled,
    );
  }

  void _section(BackupPart part, {required bool on}) =>
      _store.dispatchSync(SetBackupFormAction(toggle: part.section));

  void _setPassphrase(String text) => setState(() => _passphrase = text);

  TaskSheetVm _vm(AppState state) {
    final stage = state.backups.stage;
    switch (stage) {
      case BackupStage.choose || BackupStage.link:
        return backupFormSheet(
          _form(state),
          onSection: _section,
          onHistoryDays: (days) => _store.dispatch(
            ChangeBackupFormAction.estimate(
              SetBackupFormAction(historyDays: days),
            ),
          ),
          onLink: (id) => _store.dispatch(
            ChangeBackupFormAction.estimate(
              SetBackupFormAction(toggleLink: id),
            ),
          ),
          onPassphrase: _setPassphrase,
          onWhere: (t) =>
              _store.dispatch(ChangeBackupFormAction.where(t.place)),
          onSendLink: (link) =>
              _store.dispatch(ChangeBackupFormAction.sendLink(link)),
          onSendConnection: (c) =>
              _store.dispatchSync(SetBackupFormAction(sendConnection: c)),
          onSendPath: (path) =>
              _store.dispatchSync(SetBackupFormAction(sendPath: path)),
        );
      case BackupStage.job:
        final d = _job(state, backupJobIn(state, state.backups.job));
        return d == null
            // The job is not in the table yet (or was removed).
            ? TaskSheetVm(
                title: S.current.bakDoneTitle,
                blocks: const [],
                secondary: S.current.updClose,
              )
            : backupJobSheet(
                d,
                onWhere: (t) =>
                    _store.dispatch(ChangeBackupFormAction.where(t.place)),
                onSendLink: (link) =>
                    _store.dispatch(ChangeBackupFormAction.sendLink(link)),
                onSendConnection: (c) => _store.dispatchSync(
                  SetBackupFormAction(sendConnection: c),
                ),
                onSendPath: (path) =>
                    _store.dispatchSync(SetBackupFormAction(sendPath: path)),
                onRemove: _remove,
              );
      case BackupStage.restore ||
          BackupStage.restored ||
          BackupStage.restarting ||
          BackupStage.applied ||
          BackupStage.notApplied ||
          BackupStage.unknown ||
          BackupStage.lost ||
          null:
        return restoreSheet(
          _restore(state, stage?.restoreView ?? RestoreView.form),
          onSection: _section,
          onMode: (how) =>
              _store.dispatchSync(SetBackupFormAction(mode: how.mode)),
          onReplaceKeys: (on) =>
              _store.dispatchSync(SetBackupFormAction(replaceKeys: on)),
          onAccept: (on) =>
              _store.dispatchSync(SetBackupFormAction(acceptRights: on)),
          onPassphrase: _setPassphrase,
        );
    }
  }

  /// The passphrase as it may be sent: only where the broker takes one.
  String? get _secret {
    final d = _form(_store.state);
    return d.passphraseLocked == null && d.passphraseOk ? _passphrase : null;
  }

  void _close() => Navigator.of(context).pop();

  /// The passphrase was sent: it is kept no longer than the step that
  /// needs it.
  void _forget() {
    if (mounted) {
      setState(() => _passphrase = '');
    }
  }

  /// The primary button: one action for the step on screen (studio-rules
  /// §1, §9); the dialog only closes itself.
  FutureOr<ActionStatus>? _primary() {
    final state = _store.state;
    switch (state.backups.stage) {
      case BackupStage.choose || BackupStage.link:
        final d = _form(state);
        return _store.dispatch(
          // `keys` goes only with a passphrase the broker takes.
          BackUpAction(
            dropKeys: d.chosen.contains(BackupPart.keys) && !d.withKeys,
            passphrase: _secret,
          ),
        );
      case BackupStage.job:
        final job = backupJobIn(state, state.backups.job);
        final d = _job(state, job);
        if (job == null || d == null) {
          return null;
        }
        switch (d.primary) {
          case BackupDo.download:
            return _store.dispatch(
              DownloadBackupFileAction(
                job,
                folderTitle: S.current.bakChooseFolder(job.name),
              ),
            );
          case BackupDo.cancel:
            return _store.dispatch(CancelDownloadAction());
          case BackupDo.send:
            return _store.dispatch(SendBackupAction(job.id));
          case BackupDo.remove:
            return _remove();
          case BackupDo.show:
            _close();
            return null;
          case BackupDo.nothing:
            return null;
        }
      case BackupStage.restore:
        final d = _restore(state, RestoreView.form);
        if (d.fileName == null) {
          return _store.dispatch(UploadRestoreFileAction());
        }
        if (d.check == null) {
          return _store.dispatch(CheckRestoreAction(passphrase: _passphrase));
        }
        // Only the sections the mode and the session's rights take.
        return _store.dispatch(
          RestoreAction(
            drop: {for (final s in d.chosen.difference(d.sent)) s.section},
            passphrase: _passphrase,
          ),
        );
      case BackupStage.lost:
        // The session is no longer the site's: log in again.
        _close();
        return _store.dispatch(LeaveOnLogOutAction(LogOutAction()));
      case BackupStage.restored ||
          BackupStage.restarting ||
          BackupStage.applied ||
          BackupStage.notApplied ||
          BackupStage.unknown ||
          null:
        return null;
    }
  }

  /// *Remove*: asked here, removed by the action, the dialog closed once
  /// it is gone.
  FutureOr<ActionStatus>? _remove() {
    final j = backupJobIn(_store.state, _store.state.backups.job);
    if (j == null) {
      return null;
    }
    return _store.dispatch(
      RemoveBackupAskedAction(
        j.id,
        ask: () => ConfirmDialog.ask(
          context,
          title: S.current.bakRemoveTitle(j.name),
          message: S.current.bakRemoveNote,
          confirm: S.current.remove,
          cancel: S.current.cancel,
        ),
        removed: () {
          if (mounted) {
            _close();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, AppState>(
    // The sheet is built here, not in the converter: it also reads the
    // passphrase's length from this widget's own state.
    converter: (s) => s.state,
    // The step that needed the passphrase is done once the stage moves on
    // (a backup made, a restore applied): it is kept no longer.
    onDidChange: (_, _, state) {
      if (state.backups.stage != _stage) {
        _stage = state.backups.stage;
        _forget();
      }
    },
    builder: (context, state) => TaskSheet(
      vm: _vm(state),
      dialog: true,
      width: 680,
      onPrimary: _primary,
      onSecondary: _close,
    ),
  );
}
