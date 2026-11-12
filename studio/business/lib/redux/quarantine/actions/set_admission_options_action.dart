import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages `sys/enable_quarantine` ([holdUnknown]) or `sys/allow_all_links`
/// ([allowAll]) (config), applied with the other changes.
class SetAdmissionOptionsAction extends Action with WaitingAction {
  SetAdmissionOptionsAction({this.holdUnknown, this.allowAll});

  final bool? holdUnknown;
  final bool? allowAll;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    String word(bool v) => v ? 'on' : 'off';
    dispatchSync(
      AddChangesAction(
        [
          if (holdUnknown case final v?)
            StagedChange(
              id: 'set:$root/sys/enable_quarantine',
              op: 'Edit',
              key: '$root/sys/enable_quarantine',
              field: 'value',
              from: word(!v),
              to: word(v),
              level: 'config',
              value: v,
            ),
          if (allowAll case final v?)
            StagedChange(
              id: 'set:$root/sys/allow_all_links',
              op: 'Edit',
              key: '$root/sys/allow_all_links',
              field: 'value',
              from: word(!v),
              to: word(v),
              level: 'config',
              value: v,
            ),
        ].lock,
      ),
    );
    return null;
  }
}
