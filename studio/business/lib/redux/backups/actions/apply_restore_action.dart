import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The sections each mode of a restore takes (ADR 0048 §3.6).
const restoreSections = {
  'add': ['links', 'storage'],
  'replace': [
    'control',
    'keys',
    'dataflows',
    'storage',
    'history',
    'links',
    'packages',
  ],
};

/// `sys/backups` ▸ `restore_apply {upload, sections, mode, passphrase,
/// accept, replace_keys}`. `add` works live and answers `{done, skipped,
/// restart: false}`; `replace` stages the sections, answers `{sections,
/// restart: true}` and the broker stops: the next start applies them, and
/// Studio reconnects by itself.
class ApplyRestoreAction extends Action with NonReentrant, WaitingAction {
  ApplyRestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final upload = backups.upload;
    if (upload == null) {
      return null;
    }
    final mode = backups.mode;
    final answer = await invokeOne(
      deps.wyrm,
      '${site.root}/sys/backups',
      'restore_apply',
      valueOf({
        'upload': upload,
        'sections': [
          for (final s in restoreSections[mode] ?? const <String>[])
            if (backups.chosen.contains(s)) s,
        ],
        'mode': mode,
        if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
        if (backups.acceptRights) 'accept': true,
        if (backups.replaceKeys) 'replace_keys': true,
      }),
    );
    final restart = boolean(answer['restart']) ?? false;
    final done = strings(answer['done']);
    final skipped = strings(answer['skipped']);
    return state.copyWith.backups(
      stage: restart ? 'restarting' : 'restored',
      result: restart
          ? strings(answer['sections']).join(', ')
          : [
              if (done.isNotEmpty) done.join('\n'),
              if (skipped.isNotEmpty) skipped.join('\n'),
            ].join('\n'),
    );
  }
}
