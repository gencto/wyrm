import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages [action] on [key] with [args]: an action at level `config`
/// changes how the network runs, so it waits for Review and apply with the
/// other edits (canvas *Explorer · Actions*: Configure · staged).
class StageInvokeAction extends Action {
  StageInvokeAction(
    this.key,
    this.action,
    this.args, {
    this.display,
    this.keepEmpty = const {},
  });

  final String key;
  final String action;
  final Map<String, Object?> args;
  final String? display;

  /// Arguments staged even when empty ([argsToSend], [clearedNames]).
  final Set<String> keepEmpty;

  @override
  AppState? reduce() {
    final sent = argsToSend(args, keepEmpty: keepEmpty);
    final shown = [
      for (final e in sent.entries) '${e.key}: ${_short(e.value)}',
    ].join(', ');
    final at = DateTime.now().microsecondsSinceEpoch;
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            id: 'invoke:$key ▸ $action:$at',
            op: action.startsWith('remove')
                ? 'Remove'
                : (action.startsWith('add') ? 'Add' : 'Edit'),
            key: key,
            field: display ?? action,
            to: shown.isEmpty ? action : shown,
            level: 'config',
            action: action,
            args: sent.lock,
          ),
        ].lock,
      ),
    );
    return null;
  }

  static String _short(Object? v) {
    final s = switch (v) {
      final List<int> b => '${b.length} bytes',
      // A name cleared (`display`, ADR 0042 §4).
      '' => '""',
      _ => '$v',
    };
    return s.length > 40 ? '${s.substring(0, 39)}…' : s;
  }
}
