import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/apply_restore_action.dart';
import 'package:business/redux/backups/actions/cancel_download_action.dart';
import 'package:business/redux/backups/actions/check_restore_action.dart';
import 'package:business/redux/backups/actions/close_backup_action.dart';
import 'package:business/redux/backups/actions/create_backup_action.dart';
import 'package:business/redux/backups/actions/download_backup_action.dart';
import 'package:business/redux/backups/actions/estimate_backup_action.dart';
import 'package:business/redux/backups/actions/open_backup_action.dart';
import 'package:business/redux/backups/actions/remove_backup_action.dart';
import 'package:business/redux/backups/actions/retrieve_backups_action.dart';
import 'package:business/redux/backups/actions/retrieve_send_connections_action.dart';
import 'package:business/redux/backups/actions/send_backup_action.dart';
import 'package:business/redux/backups/actions/set_backup_form_action.dart';
import 'package:business/redux/backups/actions/upload_restore_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/wyrm/mappers/backup_mapper.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/backup_job.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/task_sheet.dart';

import '../common/app_store.dart';
import '../common/backup_sheets.dart';
import '../common/files.dart';

/// The selectors over a state, for a dialog's converter.
class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

/// The backup [id] of [state] with its live values, or null.
BackupJob? backupJobIn(AppState state, String? id) {
  final s = _Sel(state);
  final j = id == null ? null : s.backups.table[id];
  final root = s.site.root;
  return j == null
      ? null
      : backupLive(
          j,
          (leaf) => s.live.values['$root/sys/backups/$id/$leaf']?.value,
        );
}

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
    return;
  }
  store.dispatchSync(OpenBackupAction(link: link, job: job, restore: restore));
  if (link == null && job == null && !restore) {
    unawaited(store.dispatchAndWait(EstimateBackupAction()));
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupDialog(store: store),
  );
  await store.dispatchAndWait(CloseBackupAction());
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
      linkFacts: info == null
          ? null
          : '${info.id} · ${info.mode.name} · ${info.driver}',
      sections: link == null
          ? b.sections.unlock
          : [
              for (final s in linkSections)
                // The broker refuses `package` for a built-in driver.
                if (s != 'package' ||
                    (info?.driver.startsWith('pkg:') ?? false))
                  s,
            ],
      chosen: b.chosen.unlock,
      estimate: b.estimate.unlock,
      historyDays: b.historyDays,
      linkIds: s.links.view.unlock,
      offLinks: b.offLinks.unlock,
      exportSecrets: b.exportSecrets,
      viaUpstream: viaUpstreamIn(state),
      passphraseLength: _passphrase.length,
      where: b.where,
      sendLinks: b.sendLinks.unlock,
      sendLink: b.sendLink,
      connections: b.connections.unlock,
      sendConnection: b.sendConnection,
      sendPath: b.sendPath,
      keepDays: b.keepDays,
      reason: s.site.needs(
        'config',
        link == null
            ? '${s.site.root}/sys/backups'
            : '${s.site.root}/sys/links/$link',
      ),
      busy: state.wait.isWaitingForType<CreateBackupAction>(),
    );
  }

  BackupJobData? _job(AppState state) {
    final s = _Sel(state);
    final b = s.backups;
    final j = backupJobIn(state, b.job);
    return j == null
        ? null
        : BackupJobData(
            job: j,
            site: s.site.viewed ?? '',
            where: b.where,
            sendLinks: b.sendLinks.unlock,
            sendLink: b.sendLink,
            connections: b.connections.unlock,
            sendConnection: b.sendConnection,
            sendPath: b.sendPath,
            keepDays: b.keepDays,
            downloading: b.downloading == j.id,
            downloaded: b.downloaded,
            savedTo: b.savedTo,
            sending: state.wait.isWaitingForType<SendBackupAction>(),
            reason: s.site.needs('config', '${s.site.root}/sys/backups'),
          );
  }

  RestoreData _restore(AppState state) {
    final s = _Sel(state);
    final b = s.backups;
    return RestoreData(
      site: s.site.viewed ?? '',
      fileName: b.uploadName,
      size: b.uploadSize,
      uploaded: b.uploaded,
      uploading: state.wait.isWaitingForType<UploadRestoreAction>(),
      hasUpload: b.upload != null,
      check: b.check,
      chosen: b.chosen.unlock,
      mode: b.mode,
      replaceKeys: b.replaceKeys,
      acceptRights: b.acceptRights,
      exportSecrets: b.exportSecrets,
      viaUpstream: viaUpstreamIn(state),
      passphraseLength: _passphrase.length,
      busy:
          state.wait.isWaitingForType<CheckRestoreAction>() ||
          state.wait.isWaitingForType<ApplyRestoreAction>(),
      stage: b.stage ?? 'restore',
      result: b.result,
      reason: s.site.needs('config', '${s.site.root}/sys/backups'),
    );
  }

  TaskSheetVm _vm(AppState state) => switch (state.backups.stage) {
    'choose' || 'link' => backupFormSheet(_form(state)),
    'job' => switch (_job(state)) {
      final d? => backupJobSheet(d),
      // The job is not in the table yet (or was removed).
      null => TaskSheetVm(
        title: S.current.bakDoneTitle,
        blocks: const [],
        secondary: S.current.updClose,
      ),
    },
    _ => restoreSheet(_restore(state)),
  };

  /// The passphrase as it may be sent: only where the broker takes one.
  String? get _secret {
    final d = _form(_store.state);
    return d.passphraseLocked == null && d.passphraseOk ? _passphrase : null;
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _primary() async {
    final state = _store.state;
    switch (state.backups.stage) {
      case 'choose' || 'link':
        final d = _form(state);
        // `keys` goes only with a passphrase the broker takes.
        if (d.chosen.contains('keys') && !d.withKeys) {
          _store.dispatchSync(SetBackupFormAction(toggle: 'keys'));
        }
        await _store.dispatchAndWait(CreateBackupAction(passphrase: _secret));
      case 'job':
        final d = _job(state);
        switch (d?.primary) {
          case 'download':
            await _download(d!.job);
          case 'cancel':
            _store.dispatchSync(CancelDownloadAction());
          case 'send':
            await _store.dispatchAndWait(SendBackupAction(d!.job.id));
          case 'remove':
            await _remove();
          case 'show':
            _close();
        }
      case 'restore':
        final d = _restore(state);
        if (d.fileName == null) {
          await _upload();
        } else if (d.check == null) {
          await _store.dispatchAndWait(
            CheckRestoreAction(passphrase: _passphrase),
          );
        } else {
          // Only the sections the mode and the session's rights take.
          for (final s in d.chosen.difference(d.sent)) {
            _store.dispatchSync(SetBackupFormAction(toggle: s));
          }
          await _store.dispatchAndWait(
            ApplyRestoreAction(passphrase: _passphrase),
          );
        }
    }
  }

  Future<void> _upload() async {
    final f = await pickFile(extensions: const ['wyrm-backup']);
    if (f == null) {
      return;
    }
    try {
      await _store.dispatchAndWait(
        UploadRestoreAction(name: f.name, size: f.size, read: f.read),
      );
    } finally {
      await f.close();
    }
  }

  Future<void> _download(BackupJob job) async {
    final file = await saveInto(
      job.name,
      dialogTitle: S.current.bakChooseFolder(job.name),
    );
    if (file == null) {
      return;
    }
    await _store.dispatchAndWait(
      DownloadBackupAction(
        job.id,
        path: file.path,
        sha256: job.sha256,
        write: file.write,
        onDone: file.close,
        onCancel: file.discard,
      ),
    );
  }

  Future<void> _remove() async {
    final j = _job(_store.state)?.job;
    if (j == null) {
      return;
    }
    if (await ConfirmDialog.ask(
      context,
      title: S.current.bakRemoveTitle(j.name),
      message: S.current.bakRemoveNote,
      confirm: S.current.remove,
      cancel: S.current.cancel,
    )) {
      final status = await _store.dispatchAndWait(RemoveBackupAction(j.id));
      if (status.isCompletedOk && mounted) {
        _close();
      }
    }
  }

  void _toggle(String id, {required bool value}) => _store.dispatchSync(
    switch (id) {
      'replaceKeys' => SetBackupFormAction(replaceKeys: value),
      'accept' => SetBackupFormAction(acceptRights: value),
      _ => SetBackupFormAction(toggle: id),
    },
  );

  void _pick(String group, String value) {
    switch (group) {
      case 'history':
        _store.dispatchSync(SetBackupFormAction(historyDays: int.parse(value)));
        unawaited(_store.dispatchAndWait(EstimateBackupAction()));
      case 'links':
        _store.dispatchSync(SetBackupFormAction(toggleLink: value));
        unawaited(_store.dispatchAndWait(EstimateBackupAction()));
      case 'where':
        _store.dispatchSync(SetBackupFormAction(where: value));
        // One link the host lists: it is the choice.
        final links = _store.state.backups.sendLinks;
        if (value == 'store' && links.length == 1) {
          _pick('sendLink', links.first.link);
        }
      case 'sendLink':
        _store.dispatchSync(SetBackupFormAction(sendLink: value));
        unawaited(
          _store.dispatchAndWait(RetrieveSendConnectionsAction(value)),
        );
      case 'sendConnection':
        _store.dispatchSync(SetBackupFormAction(sendConnection: value));
      case 'mode':
        _store.dispatchSync(SetBackupFormAction(mode: value));
    }
  }

  void _text(String id, String text) {
    if (id == 'passphrase') {
      setState(() => _passphrase = text);
    } else if (id == 'sendPath') {
      _store.dispatchSync(SetBackupFormAction(sendPath: text));
    }
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, AppState>(
    // The sheet is built here, not in the converter: it also reads the
    // passphrase's length from this widget's own state.
    converter: (s) => s.state,
    builder: (context, state) => TaskSheet(
      vm: _vm(state),
      dialog: true,
      width: 680,
      onPrimary: () => unawaited(_primary()),
      onSecondary: _close,
      onToggle: _toggle,
      onPick: _pick,
      onText: _text,
      onAction: (a) {
        if (a == 'remove') {
          unawaited(_remove());
        }
      },
    ),
  );
}
