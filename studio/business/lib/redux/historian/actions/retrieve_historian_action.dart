import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/sys_answers.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';
import 'follow_history_action.dart';

/// Reads the historian of the site (`sys/history`): its values (rows
/// written, size, retention …) and each watch group with its settings and
/// the keys its watches record (a watch shows its key as its display name).
/// No recorded values: those are read for the points the user picks
/// (`RetrieveSeriesAction`).
class RetrieveHistorianAction extends Action with WaitingAction {
  @override
  Action again() => RetrieveHistorianAction();

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/history';
    final (top, values) = await (
      listOf(api, base),
      readValues(api, '$base/*'),
    ).wait;
    // One list per group, all at once: the groups and their points come
    // first, the recorded values only for the points the user picks.
    final named = [
      for (final g in top)
        if (g.meta.ty == null && g.name != 'sinks') g.name,
    ];
    Future<List<Child>> watchesOf(String group) async {
      try {
        return await api.children('$base/$group');
      } on WyrmException {
        return const [];
      }
    }

    final (lists, groupValues) = await (
      Future.wait([for (final n in named) watchesOf(n)]),
      readValues(api, '$base/*/*'),
    ).wait;
    final groups = <WatchGroup>[];
    final unread = Unread();
    for (final (i, name) in named.indexed) {
      // a group this client cannot read is left out; the user is told
      final group = unread.take(
        watchGroupOf(name, {
          for (final e in groupValues.entries)
            if (e.key.startsWith('$base/$name/'))
              e.key.substring('$base/$name/'.length): e.value,
        }, lists[i]),
        name: name,
        where: '$base/$name',
      );
      if (group != null) {
        groups.add(group);
      }
    }
    // a value of the statistics this client cannot read is left out; the
    // user is told
    final stats = {
      for (final e in values.entries)
        e.key.split('/').last: ?unread.take(
          historianStatOf(e.key.split('/').last, e.value),
          name: e.key.split('/').last,
          where: base,
        ),
    };
    if (unread.problem(key: base, call: 'list') case final p?) {
      dispatchSync(AddProblemAction(p));
    }
    final selected = historian.selected ?? groups.firstOrNull?.name;
    final shown = groups.where((g) => g.name == selected).firstOrNull;
    return state.copyWith.historian(
      groups: groups.lock,
      stats: stats.lock,
      selected: selected,
      // A picked point that is no longer recorded leaves the trend.
      points: historian.points
          .where((k) => shown?.keys.contains(k) ?? false)
          .toIList(),
    );
  }

  /// While History is shown, its subscriptions follow the new group and points.
  @override
  void after() {
    super.after();
    dispatchSync(FollowHistoryAction());
  }
}
