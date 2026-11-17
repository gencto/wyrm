import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/change_op.dart';
import 'package:models/log_level.dart';
import 'package:models/staged_change.dart';
import 'package:models/staged_change_kind.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../changes/actions/remove_change_action.dart';
import '../../common/action.dart';

/// A level is picked for the broker's own log: it stages `sys/log_level`
/// in Review and apply (an enum node: its code is written, its name
/// shown); picking the broker's own level again takes the staged change
/// back, and nothing is staged then.
class StageLogLevelAction extends Action {
  StageLogLevelAction(this.level);

  final LogLevel level;

  @override
  AppState? reduce() {
    final key = '${site.root}/sys/log_level';
    final current = brokerLogLevel;
    if (level == current) {
      if (stagedLogLevel case final staged?) {
        dispatchSync(RemoveChangeAction(staged.id));
      }
      return null;
    }
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            id: StagedChangeKind.set.idOf(key),
            op: ChangeOp.edit,
            key: key,
            field: 'value',
            from: current?.wire ?? '—',
            to: level.wire,
            level: Perm.config,
            value: level.code,
          ),
        ].lock,
      ),
    );
    return null;
  }
}
