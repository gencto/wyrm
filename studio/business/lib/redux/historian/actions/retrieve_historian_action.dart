import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

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
    for (final (i, name) in named.indexed) {
      final watches = lists[i];
      Value? v(String k) => groupValues['$base/$name/$k'];
      final ws = [
        for (final w in watches)
          if (w.meta.ty == null) w,
      ];
      groups.add(
        WatchGroup(
          name: name,
          loggingType: str(v('logging_type')) ?? '',
          interval: number(v('interval')),
          flush: number(v('buffer_flush_time')),
          watchIds: [for (final w in ws) w.name].lock,
          keys: [for (final w in ws) w.meta.displayName ?? w.name].lock,
        ),
      );
    }
    final selected = historian.selected ?? groups.firstOrNull?.name;
    final shown = groups.where((g) => g.name == selected).firstOrNull;
    return state.copyWith.historian(
      groups: groups.lock,
      stats: {
        for (final e in values.entries)
          e.key.split('/').last: text(e.value) ?? '',
      }.lock,
      selected: selected,
      // A picked point that is no longer recorded leaves the trend.
      points: historian.points
          .where((k) => shown?.keys.contains(k) ?? false)
          .toIList(),
    );
  }
}
