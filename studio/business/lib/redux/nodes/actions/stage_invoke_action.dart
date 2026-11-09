import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages [action] on [key] with [args]: an action at level `config`
/// changes how the network runs, so it waits for Review and apply with the
/// other edits (canvas *Explorer · Actions*: Configure · staged).
class StageInvokeAction extends Action {
  StageInvokeAction(this.key, this.action, this.args, {this.display});

  final String key;
  final String action;
  final Map<String, Object?> args;
  final String? display;

  @override
  AppState? reduce() {
    final shown = [
      for (final e in args.entries)
        if (e.value != null && e.value != '') '${e.key}: ${_short(e.value)}',
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
            args: {
              for (final e in args.entries)
                if (e.value != null && e.value != '') e.key: e.value,
            }.lock,
          ),
        ].lock,
      ),
    );
    return null;
  }

  static String _short(Object? v) {
    final s = v is List<int> ? '${v.length} bytes' : '$v';
    return s.length > 40 ? '${s.substring(0, 39)}…' : s;
  }
}
