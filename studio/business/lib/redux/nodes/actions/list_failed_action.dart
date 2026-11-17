import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';
import 'retry_read_action.dart';
import 'set_children_action.dart';
import 'set_list_failed_action.dart';

/// The list of [parent] failed with [error]: the branch shows no children.
/// A node the user may not list is simply empty for them; any other failure
/// is also the `read failed` mark on its row and a quiet problem
/// (docs/design/specs/errors.md §4) — one state for all of it.
class ListFailedAction extends Action {
  ListFailedAction(this.parent, this.error);

  final String parent;
  final Object error;

  @override
  AppState reduce() {
    dispatchSync(
      SetChildrenAction(parent, const IListConst([])),
      notify: false,
    );
    if (error case final WyrmException w
        when w.status.known != Status.permissionDenied) {
      final e = refusalOf(w, key: parent, call: 'list');
      dispatchSync(SetListFailedAction(parent, w.status.name), notify: false);
      dispatchSync(
        AddProblemAction(
          e.copyWith(
            quiet: true,
            stream: e.kind == ErrorKind.reach ? e.site : null,
            retry: () => RetryReadAction(parent),
          ),
        ),
        notify: false,
      );
    }
    return state;
  }
}
