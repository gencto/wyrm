import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/log_level.dart';
import 'package:models/sys_status.dart';
import 'package:models/sys_value.dart';

import 'decoded.dart';
import 'live_fields.dart';

const _shape = 'sys';

/// `sys/log_level`: an enum node, its code (`0 error … 4 trace`) or its
/// name.
Decoded<LogLevel?> logLevelOf(Object? v) => switch (v) {
  null => const Valid(null),
  final num n when n == n.truncateToDouble() => switch (LogLevel.fromCode(
    n.toInt(),
  )) {
    final l? => Valid(l),
    null => const Invalid(_shape, 'log_level', 'not a level code'),
  },
  final String s => switch (LogLevel.fromWire(s)) {
    final l? => Valid(l),
    null => const Invalid(_shape, 'log_level', 'not a level name'),
  },
  _ => const Invalid(_shape, 'log_level', 'not a code or a name'),
};

/// The keys below `sys` [sysStatusOf] reads: every [SysValue] and the
/// broker's texts.
final List<String> sysStatusKeys = [
  for (final v in SysValue.values) v.key,
  'version',
  'zenoh_version',
  'distribution',
  'start_time',
  'log_level',
];

/// What `sys` serves about the broker, from [value] (the live value of a
/// key below `sys`, as plain Dart; null when none arrived). Each value is
/// decoded on its own: one that is not of its type is left out **and
/// logged** with its key and [where] (`sys of plant`), the others stay.
SysStatus sysStatusOf(Object? Function(String key) value, String where) =>
    SysStatus(
      numbers: {
        for (final s in SysValue.values)
          s: ?liveNumber(value(s.key), _shape, s.key).orWarn(where),
      }.lock,
      version: liveText(value('version'), _shape, 'version').orWarn(where),
      zenohVersion: liveText(
        value('zenoh_version'),
        _shape,
        'zenoh_version',
      ).orWarn(where),
      distribution: liveText(
        value('distribution'),
        _shape,
        'distribution',
      ).orWarn(where),
      startTime: liveTime(
        value('start_time'),
        _shape,
        'start_time',
      ).orWarn(where),
      logLevel: logLevelOf(value('log_level')).orWarn(where),
    );
