import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';
import 'package:models/staged_change.dart';
import 'package:models/workspace.dart';

import '../redux/app_state.dart';

/// A staged change as the review panel shows it: whether the user's grants
/// reach the level it needs, and the level they have on its key.
final class ReviewCard {
  const ReviewCard({
    required this.change,
    required this.allowed,
    required this.have,
  });

  final StagedChange change;
  final bool allowed;
  final String have;
}

/// The problems pill: how many it counts and whether one is a fault of the
/// broker or of Studio.
final class ProblemsCount {
  const ProblemsCount({
    required this.count,
    required this.bad,
    required this.open,
  });

  final int count;
  final bool bad;
  final bool open;
}

/// A node the search palette finds: its key, the name it shows (its
/// display name when it has one), and what its icon is drawn from.
final class SearchNode {
  const SearchNode({
    required this.key,
    required this.title,
    this.profile,
    this.value = false,
  });

  final String key;
  final String title;
  final String? profile;

  /// The node holds a value.
  final bool value;
}

/// What the Studio shell shows, computed from the state.
extension ShellSelect on Selectors {
  /// The sites the viewed one is reached through (empty: the site logged
  /// into, or one reached directly).
  List<String> get viewedVia {
    final home = site.name ?? '';
    final viewed = site.viewed ?? home;
    final here = site.choices.where((c) => c.site == viewed).firstOrNull;
    return {
      ?here?.via,
      if (viewed != home) home,
    }.toList();
  }

  /// The staged changes, with the level each needs checked against the
  /// user's own grants.
  List<ReviewCard> get reviewCards => [
    for (final id in changes.view)
      if (changes.table[id] case final c?)
        ReviewCard(
          change: c,
          allowed: site.can(c.level, c.key),
          have: site.levelOn(c.key),
        ),
  ];

  /// `sys/audit/<link>` the applied writes are recorded in: the one link
  /// the staged changes touch, or all of `sys/audit`.
  String get reviewAudit {
    final links = {
      for (final id in changes.view)
        if (changes.table[id]?.key.split('/') case final p?
            when p.length > 3 && p[2] == 'downstream')
          p[3],
    };
    return links.length == 1 ? 'sys/audit/${links.single}' : 'sys/audit';
  }

  /// The pill: hidden at 0, shown while the drawer is open (to close it).
  ProblemsCount? get problemsCount {
    final p = problems;
    if (p.unread == 0 && !p.open) {
      return null;
    }
    final n = p.open ? p.items.length : p.unread;
    return ProblemsCount(
      count: n,
      bad: p.items.take(n).any((e) => e.kind == .broker || e.kind == .studio),
      open: p.open,
    );
  }

  /// The workspaces reading again what they show.
  ISet<Workspace> get refreshingWorkspaces => {
    for (final w in Workspace.values)
      if (refreshing(w)) w,
  }.lock;

  /// The nodes the search palette finds (the first 400 the tree holds).
  List<SearchNode> get searchNodes => [
    for (final k in nodes.view.take(400))
      SearchNode(
        key: k,
        // A node's display name when it has one; the key below it still
        // finds it by name.
        title: switch (nodes.table[k]) {
          NodeInfo(:final display?, :final name)
              when display.trim().isNotEmpty && display != name =>
            display,
          final n => n?.name ?? k,
        },
        profile: nodes.table[k]?.profile,
        value: nodes.table[k]?.type != null,
      ),
  ];
}
