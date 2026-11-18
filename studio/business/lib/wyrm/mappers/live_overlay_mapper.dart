import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/flow_summary.dart';
import 'package:models/live_value.dart';
import 'package:models/watch_group.dart';

import '../decode/backup_job.dart';
import '../decode/flow_val.dart';
import '../decode/live_fields.dart' show liveNumber;
import '../decode/live_values.dart';
import '../decode/package_info.dart';
import '../decode/sys_answers.dart';

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
/// `interval`, `buffer_flush_time`) from [values] where they are live. A
/// live value of another shape keeps what the group holds; it is recorded
/// where it arrives ([warnUnreadLive]), not here: a selector calls this
/// on every rebuild.
IList<WatchGroup> liveGroups(
  IList<WatchGroup> groups,
  String base,
  IMap<String, LiveValue> values,
) => [
  for (final g in groups)
    () {
      Object? v(String k) => values['$base/${g.name}/$k']?.value;
      return g.copyWith(
        logging: liveLoggingOf(v('logging_type')).orNull ?? g.logging,
        interval:
            liveNumber(v('interval'), 'watch group', 'interval').orNull ??
            g.interval,
        flush:
            liveNumber(
              v('buffer_flush_time'),
              'watch group',
              'buffer_flush_time',
            ).orNull ??
            g.flush,
      );
    }(),
].lock;

/// [f] under its live `~val` [v], when there is one ([flowUnderLive]): its
/// state, version, deployer and error; a value Studio cannot read says
/// the state is not known and keeps the last version read.
FlowSummary liveFlow(FlowSummary f, LiveValue? v) =>
    v == null ? f : flowUnderLive(f, flowValOf(v.value));

/// Records each value of [changed] (one batch of the live values, under
/// the site [root]) that the screens read and that is not of its shape: a
/// flow's `~val`, the settings of a watch group, and a link's `state` and
/// `restore_points`. Called once per batch
/// where the values arrive, so a value is recorded once per change and
/// the selectors that read it record nothing.
void warnUnreadLive(Map<String, LiveValue?> changed, String root) {
  final flows = '$root/dataflows/';
  final history = '$root/sys/history/';
  final links = '$root/sys/links/';
  final backups = '$root/sys/backups/';
  for (final MapEntry(:key, :value) in changed.entries) {
    if (value == null) {
      continue;
    }
    if (key.startsWith(flows)) {
      final id = key.substring(flows.length);
      if (!id.contains('/')) {
        flowValOf(value.value).record(key);
      }
    } else if (key.startsWith(links)) {
      final parts = key.substring(links.length).split('/');
      if (parts.length != 2) {
        continue;
      }
      final where = 'sys/links/${parts.first}/${parts.last}';
      switch (parts.last) {
        case _stateLeaf:
          linkStateSampleOf(value.value).record(where);
        case _pointsLeaf:
          restorePointsOf(value.value, where: where).record(where);
      }
    } else if (key.startsWith(backups)) {
      final parts = key.substring(backups.length).split('/');
      if (parts.length == 2 && backupLeaves.contains(parts.last)) {
        // the one leaf that changed, laid over an empty job: only its
        // own fault is recorded
        backupLiveOf(
          BackupJob(id: parts.first),
          (leaf) => leaf == parts.last ? value.value : null,
          '$backups${parts.first}',
        );
      }
    } else if (key.startsWith(history)) {
      final parts = key.substring(history.length).split('/');
      if (parts.length != 2) {
        continue;
      }
      final where = '$history${parts.first}';
      switch (parts.last) {
        case _loggingLeaf:
          liveLoggingOf(value.value).record(where);
        case _intervalLeaf || _flushLeaf:
          liveNumber(value.value, 'watch group', parts.last).record(where);
      }
    }
  }
}

const _stateLeaf = 'state';
const _pointsLeaf = 'restore_points';
const _loggingLeaf = 'logging_type';
const _intervalLeaf = 'interval';
const _flushLeaf = 'buffer_flush_time';
