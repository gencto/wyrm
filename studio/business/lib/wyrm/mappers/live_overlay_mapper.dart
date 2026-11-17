import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';
import 'package:models/live_value.dart';
import 'package:models/logging_type.dart';
import 'package:models/watch_group.dart';

import '../decode/live_fields.dart' show liveName, liveNumber;
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
      final where = '$base/${g.name}';
      // a live value of another shape keeps what the group holds, and
      // is logged with its leaf
      return g.copyWith(
        loggingType:
            liveName(
              v('logging_type'),
              LoggingType.fromWire,
              'watch group',
              'logging_type',
            ).orWarn(where) ??
            g.loggingType,
        interval:
            liveNumber(
              v('interval'),
              'watch group',
              'interval',
            ).orWarn(where) ??
            g.interval,
        flush:
            liveNumber(
              v('buffer_flush_time'),
              'watch group',
              'buffer_flush_time',
            ).orWarn(where) ??
            g.flush,
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
