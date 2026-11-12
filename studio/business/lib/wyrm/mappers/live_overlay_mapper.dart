import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';
import 'package:models/live_value.dart';
import 'package:models/watch_group.dart';

import 'flow_value_mapper.dart';

/// A live value as the historian's text: a number without a trailing `.0`,
/// a text or a bool as it is; null for anything else.
String? liveText(Object? v) => switch (v) {
  final String s => s,
  final int i => '$i',
  final double d when d == d.truncateToDouble() && d.abs() < 1e15 =>
    '${d.toInt()}',
  final double d => '$d',
  final bool b => '$b',
  _ => null,
};

/// The historian's values (`<base>/<name>`: rows written, size, oldest
/// day …) from [values] while History follows them, over [read] (what a
/// one-shot read held).
IMap<String, String> liveStats(
  IMap<String, String> read,
  String base,
  IMap<String, LiveValue> values,
) {
  var out = read;
  for (final MapEntry(:key, :value) in values.entries) {
    if (!key.startsWith('$base/')) {
      continue;
    }
    final name = key.substring(base.length + 1);
    if (name.contains('/')) {
      continue;
    }
    if (liveText(value.value) case final t?) {
      out = out.add(name, t);
    }
  }
  return out;
}

/// [groups] with each group's settings (`<base>/<group>/logging_type`,
/// `interval`, `buffer_flush_time`) from [values] where they are live.
IList<WatchGroup> liveGroups(
  IList<WatchGroup> groups,
  String base,
  IMap<String, LiveValue> values,
) => [
  for (final g in groups)
    () {
      Object? v(String k) => values['$base/${g.name}/$k']?.value;
      return g.copyWith(
        loggingType: switch (v('logging_type')) {
          final String s => s,
          _ => g.loggingType,
        },
        interval: switch (v('interval')) {
          final num n => n,
          _ => g.interval,
        },
        flush: switch (v('buffer_flush_time')) {
          final num n => n,
          _ => g.flush,
        },
      );
    }(),
].lock;

/// [f] with its running state, version, deployer and error from its live
/// `~val` [v] (`{state, error, version, deployed_by}`), when there is one.
FlowSummary liveFlow(FlowSummary f, LiveValue? v) {
  if (v == null) {
    return f;
  }
  final l = flowSummaryOfValue(f.id, v.value);
  return f.copyWith(
    version: l.version ?? f.version,
    deployedBy: l.deployedBy,
    problem: l.problem,
    draft: l.draft,
    running: l.running,
  );
}
