import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages a `set` of the point [key] to [value] (Explorer › edit in place),
/// at the level its meta asks for (`write` or `config`).
class StageValueAction extends Action {
  StageValueAction(this.key, this.value, {this.from = '—'});

  final String key;
  final Object? value;
  final String from;

  @override
  AppState? reduce() {
    final level =
        state.nodes.detail[key]?.writable ??
        state.nodes.table[key]?.writable ??
        'write';
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            id: 'set:$key',
            op: 'Edit',
            key: key,
            field: 'value',
            from: from,
            to: '$value',
            level: level,
            value: value,
          ),
        ].lock,
      ),
    );
    return null;
  }
}
