import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';
import '../../services/live_lists/live_lists_dispatcher.dart';
import 'follow_list_action.dart';

/// The live list of [parent] failed with [error], as the tree's lists do
/// (docs/design/specs/errors.md §4): a list the user may not read is simply
/// empty; another refusal empties it too and is a quiet problem (a toast
/// and a line in Problems). A lost broker keeps what is shown (the list
/// opens again by itself) and is one problem of its site's stream.
class LiveListFailedAction extends Action {
  LiveListFailedAction(this.parent, this.error);

  final String parent;
  final Object error;

  @override
  Future<AppState?> reduce() async {
    final e = switch (error) {
      WyrmException(:final status)
          when status.known == Status.permissionDenied =>
        null,
      final WyrmException w => refusalOf(
        w,
        key: parent,
        call: const .known(.list),
      ),
      _ => faultOf(
        error,
        null,
        step: const .known(.list),
      ).copyWith(key: parent),
    };
    if (e?.kind != ErrorKind.reach) {
      await dispatchAndWait(FollowListAction(parent, const ListChange.all([])));
    }
    if (e != null) {
      dispatchSync(
        AddProblemAction(
          e.copyWith(
            quiet: true,
            stream: e.kind == ErrorKind.reach ? e.site : null,
          ),
        ),
      );
    }
    return null;
  }
}
