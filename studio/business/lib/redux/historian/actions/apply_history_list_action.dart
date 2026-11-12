import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../services/live_lists/live_lists_dispatcher.dart';
import 'follow_history_action.dart';
import 'retrieve_group_watches_action.dart';

/// One update of a live list History follows: `sys/history` (the groups)
/// or `sys/history/<group>` (that group's watches). A group added is read
/// once for its watches (only the selected group is listed live); a group
/// gone leaves the sidebar, and when it was the selected one the first
/// group left is selected. A watch gone takes its point off the trend.
/// Updates of another site than the one on screen are dropped.
class ApplyHistoryListAction extends Action {
  ApplyHistoryListAction(this.parent, this.change);

  final String parent;
  final ListChange change;

  /// A child of `sys/history` that is a watch group: a node with no value
  /// type, not the sinks folder.
  static bool isGroup(Child c) => c.meta.ty == null && c.name != 'sinks';

  /// A child of a group that is a watch (its values are not).
  static bool isWatch(Child c) => c.meta.ty == null;

  final _read = <String>[];

  @override
  AppState? reduce() {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final base = '$root/sys/history';
    if (parent == base) {
      return _groups();
    }
    if (parent.startsWith('$base/')) {
      final name = parent.substring(base.length + 1);
      if (!name.contains('/')) {
        return _watches(name);
      }
    }
    return null;
  }

  AppState? _groups() {
    final old = {for (final g in historian.groups) g.name: g};
    final List<WatchGroup> groups;
    if (change.children case final all?) {
      groups = [
        for (final c in all)
          if (isGroup(c)) old[c.name] ?? WatchGroup(name: c.name),
      ];
      // A full list (a first answer, a reconnect): every group not listed
      // live is read again for its watches.
      _read.addAll([for (final g in groups) g.name]);
    } else if (change.child case final c?) {
      if (!isGroup(c) || old.containsKey(c.name)) {
        return null;
      }
      groups = [...historian.groups, WatchGroup(name: c.name)];
      _read.add(c.name);
    } else {
      final gone = change.name;
      if (!old.containsKey(gone)) {
        return null;
      }
      groups = [
        for (final g in historian.groups)
          if (g.name != gone) g,
      ];
    }
    var selected = historian.selected;
    if (!groups.any((g) => g.name == selected)) {
      selected = groups.firstOrNull?.name;
    }
    final moved = selected != historian.selected;
    return state.copyWith.historian(
      groups: groups.lock,
      selected: selected,
      points: moved ? const IListConst([]) : historian.points,
      series: moved ? const IMapConst({}) : historian.series,
    );
  }

  AppState? _watches(String name) {
    final i = historian.groups.indexWhere((g) => g.name == name);
    if (i < 0) {
      return null;
    }
    final g = historian.groups[i];
    final ids = g.watchIds.toList();
    final keys = g.keys.toList();
    if (change.children case final all?) {
      ids.clear();
      keys.clear();
      for (final c in all.where(isWatch)) {
        ids.add(c.name);
        keys.add(c.meta.displayName ?? c.name);
      }
    } else if (change.child case final c?) {
      if (!isWatch(c)) {
        return null;
      }
      final at = ids.indexOf(c.name);
      final key = c.meta.displayName ?? c.name;
      if (at < 0) {
        ids.add(c.name);
        keys.add(key);
      } else {
        keys[at] = key;
      }
    } else {
      final at = ids.indexOf(change.name!);
      if (at < 0) {
        return null;
      }
      ids.removeAt(at);
      keys.removeAt(at);
    }
    final next = g.copyWith(watchIds: ids.lock, keys: keys.lock);
    if (next == g) {
      return null;
    }
    final shown = name == historian.selected;
    // A picked point that is no longer recorded leaves the trend.
    final points = shown
        ? historian.points.where(keys.contains).toIList()
        : historian.points;
    return state.copyWith.historian(
      groups: historian.groups.replace(i, next),
      points: points,
      series: {
        for (final e in historian.series.entries)
          if (points.contains(e.key)) e.key: e.value,
      }.lock,
    );
  }

  @override
  void after() {
    super.after();
    // The selected group is listed live; the others are read once.
    final read = [
      for (final n in _read)
        if (n != historian.selected) n,
    ];
    if (read.isNotEmpty) {
      unawaited(dispatchAndWait(RetrieveGroupWatchesAction(read)));
    }
    dispatchSync(FollowHistoryAction());
  }
}
