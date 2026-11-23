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
import 'package:business/wyrm/backup_plan.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_stage.dart';
import 'package:ui/overlays/backup_data.dart';
import 'package:ui/overlays/backup_sheet.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../common/app_store.dart';
import '../common/backup_file_actions.dart';
import '../mappers/backup_mappers.dart';
import '../mappers/rights_mappers.dart';
import '../navigation/leave_on_log_out_action.dart';

/// The selectors over a state, for a dialog's converter.
class _Sel with Selectors, StateAlone {
  _Sel(this.state);

  @override
  final AppState state;
}

/// The waits the backup dialog draws. They are part of what its connector
/// compares: the state does not change when an action starts or ends, so
/// the dialog is built again only because one of these did.
final class _Busy {
  _Busy(Waiting w)
    : creating = w.on<CreateBackupAction>(),
      sending = w.on<SendBackupAction>(),
      uploading = w.on<UploadRestoreAction>(),
      restoring = w.on<CheckRestoreAction>() || w.on<ApplyRestoreAction>();

  final bool creating;
  final bool sending;
  final bool uploading;
  final bool restoring;

  @override
  bool operator ==(Object other) =>
      other is _Busy &&
      other.creating == creating &&
      other.sending == sending &&
      other.uploading == uploading &&
      other.restoring == restoring;

  @override
  int get hashCode => Object.hash(creating, sending, uploading, restoring);
}

/// The backup [id] of [state] with its live values, or null.
BackupJob? backupJobIn(AppState state, String? id) =>
    id == null ? null : _Sel(state).backupJob(id);

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
  if (!context.mounted || !_Sel(store.state).backupsOffered) {
    // A broker without `sys/backups`, with one Studio does not read, or
    // with one that lists no section: the callers lock their buttons with
    // the reason, so this is only a broker whose answer changed meanwhile.
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

  BackupFormPlan _formPlan(AppState state) =>
      _Sel(state).backupFormPlan(passphraseLength: _passphrase.length);

  RestorePlan _restorePlan(AppState state) =>
      _Sel(state).restorePlan(passphraseLength: _passphrase.length);

  BackupFormData _form(AppState state, _Busy busy) {
    final s = _Sel(state);
    final link = s.backups.link;
    return backupFormDataOf(
      site: s.site.viewed ?? '',
      b: state.backups,
      plan: _formPlan(state),
      link: link == null ? null : s.links.table[link],
      linkIds: s.links.view.unlock,
      reason: s.site
          .lacks(
            Perm.config,
            link == null
                ? '${s.site.root}/sys/backups'
                : '${s.site.root}/sys/links/$link',
          )
          ?.disabled,
      busy: busy.creating,
    );
  }

  BackupJobData? _job(AppState state, _Busy busy, BackupJob? j) {
    final s = _Sel(state);
    return j == null
        ? null
        : backupJobDataOf(
            site: s.site.viewed ?? '',
            b: state.backups,
            job: j,
            plan: s.backupJobPlan(j),
            sending: busy.sending,
            reason: s.site
                .lacks(Perm.config, '${s.site.root}/sys/backups')
                ?.disabled,
          );
  }

  RestoreData _restore(AppState state, _Busy busy, RestoreView view) {
    final s = _Sel(state);
    return restoreDataOf(
      site: s.site.viewed ?? '',
      b: state.backups,
      plan: _restorePlan(state),
      file: s.restoreFilePlan,
      view: view,
      uploading: busy.uploading,
      busy: busy.restoring,
      reason: s.site.lacks(Perm.config, '${s.site.root}/sys/backups')?.disabled,
    );
  }

  void _section(BackupPart part, {required bool on}) =>
      _store.dispatchSync(SetBackupFormAction(toggle: part.section));

  void _setPassphrase(String text) => setState(() => _passphrase = text);

  TaskSheetVm _vm(AppState state, _Busy busy) {
    final stage = state.backups.stage;
    switch (stage) {
      case BackupStage.choose || BackupStage.link:
        return backupFormSheet(
          _form(state, busy),
          onSection: _section,
          onHistoryRange: (range) => _store.dispatch(
            ChangeBackupFormAction.estimate(
              SetBackupFormAction(historyDays: range.days),
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
        final d = _job(state, busy, backupJobIn(state, state.backups.job));
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
          _restore(state, busy, stage?.restoreView ?? RestoreView.form),
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
        // What goes, and whether it may, is decided by the action from
        // its plan (`backupFormPlanOf`): the dialog hands over what was
        // typed.
        return _store.dispatch(BackUpAction(passphrase: _passphrase));
      case BackupStage.job:
        final job = backupJobIn(state, state.backups.job);
        if (job == null) {
          return null;
        }
        switch (_Sel(state).backupJobPlan(job).step) {
          case BackupJobStep.download:
            return _store.dispatch(
              DownloadBackupFileAction(
                job,
                folderTitle: S.current.bakChooseFolder(job.name),
              ),
            );
          case BackupJobStep.cancel:
            return _store.dispatch(CancelDownloadAction());
          case BackupJobStep.send:
            return _store.dispatch(SendBackupAction(job.id));
          case BackupJobStep.remove:
            return _remove();
          case BackupJobStep.show:
            _close();
            return null;
          case BackupJobStep.nothing:
            return null;
        }
      case BackupStage.restore:
        // Which step the button is at is decided in `business`
        // (`restoreFilePlanOf`); what goes, and whether it may, by each
        // action from its plan.
        return switch (_Sel(state).restoreFilePlan.step) {
          RestoreFileStep.choose => _store.dispatch(UploadRestoreFileAction()),
          RestoreFileStep.uploading => null,
          RestoreFileStep.check => _store.dispatch(
            CheckRestoreAction(passphrase: _passphrase),
          ),
          RestoreFileStep.restore => _store.dispatch(
            RestoreAction(passphrase: _passphrase),
          ),
        };
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
  Widget build(BuildContext context) =>
      StoreConnector<AppState, (AppState, _Busy)>(
        // The sheet is built here, not in the converter: it also reads the
        // passphrase's length from this widget's own state. The waits are read
        // in the converter, so one that starts or ends builds the sheet again.
        converter: (s) => (s.state, _Busy(Waiting(s.isWaiting))),
        // The step that needed the passphrase is done once the stage moves on
        // (a backup made, a restore applied): it is kept no longer.
        onDidChange: (_, _, seen) {
          final stage = seen.$1.backups.stage;
          if (stage != _stage) {
            _stage = stage;
            _forget();
          }
        },
        builder: (context, seen) => TaskSheet(
          vm: _vm(seen.$1, seen.$2),
          dialog: true,
          width: 680,
          onPrimary: _primary,
          onSecondary: _close,
        ),
      );
}
