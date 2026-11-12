import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'apply_history_list_action.dart';

/// Reads once, all at once, the watches of the watch groups [names]: the
/// groups History does not list live (only the selected one is), so their
/// point counts are right when they appear or the list is read again. A
/// group the user may not list keeps what it showed.
class RetrieveGroupWatchesAction extends Action {
  RetrieveGroupWatchesAction(this.names);

  final List<String> names;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || names.isEmpty) {
      return null;
    }
    final base = '$root/sys/history';
    final api = deps.wyrm;
    Future<List<Child>?> watchesOf(String group) async {
      try {
        return await api.children('$base/$group');
      } on WyrmException {
        return null;
      }
    }

    final got = await Future.wait([for (final n in names) watchesOf(n)]);
    if (site.root != root) {
      return null;
    }
    var groups = historian.groups;
    for (final (i, name) in names.indexed) {
      final ws = got[i]?.where(ApplyHistoryListAction.isWatch).toList();
      final at = groups.indexWhere((g) => g.name == name);
      // The selected group is listed live by now: its list is the truth.
      if (ws == null || at < 0 || name == historian.selected) {
        continue;
      }
      groups = groups.replace(
        at,
        groups[at].copyWith(
          watchIds: [for (final w in ws) w.name].lock,
          keys: [for (final w in ws) w.meta.displayName ?? w.name].lock,
        ),
      );
    }
    return state.copyWith.historian(groups: groups);
  }
}
