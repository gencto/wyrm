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
    final top = await listOf(api, base);
    final values = await readValues(api, '$base/*');
    final groups = <WatchGroup>[];
    final groupValues = await readValues(api, '$base/*/*');
    for (final g in top) {
      if (g.meta.ty != null || g.name == 'sinks') {
        continue;
      }
      List<Child> watches;
      try {
        watches = await api.children('$base/${g.name}');
      } on WyrmException {
        watches = const [];
      }
      Value? v(String k) => groupValues['$base/${g.name}/$k'];
      final ws = [
        for (final w in watches)
          if (w.meta.ty == null) w,
      ];
      groups.add(
        WatchGroup(
          name: g.name,
          loggingType: str(v('logging_type')) ?? '',
          interval: number(v('interval')),
          flush: number(v('buffer_flush_time')),
          watchIds: [for (final w in ws) w.name].lock,
          keys: [for (final w in ws) w.meta.displayName ?? w.name].lock,
        ),
      );
    }
    return state.copyWith.historian(
      groups: groups.lock,
      stats: {
        for (final e in values.entries)
          e.key.split('/').last: text(e.value) ?? '',
      }.lock,
      selected: historian.selected ?? groups.firstOrNull?.name,
    );
  }
}
