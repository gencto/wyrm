import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/package_info.dart';
import 'package:models/restore_point.dart';
import 'package:models/update_report.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The full `~meta` of `sys/packages/<name>` (`wy:package`) as a
/// [PackageInfo].
PackageInfo packageInfoOf(String name, NodeMeta m) => PackageInfo(
  name: name,
  version: str(attrOf(m, 'version')) ?? '',
  kind: str(attrOf(m, 'kind')) ?? 'process',
  source: str(attrOf(m, 'source')),
  sha256: str(attrOf(m, 'sha256')),
);

int _int(Object? v) => switch (v) {
  final int n => n,
  final double d => d.toInt(),
  _ => 0,
};

IList<String> _strings(Object? v) => switch (v) {
  final List<Object?> l => [
    for (final e in l)
      if (e is String) e,
  ].lock,
  _ => const IListConst([]),
};

/// `sys/packages/<name>/last_update` (a map as plain Dart) as an
/// [UpdateReport]; null for the empty map of a package never updated.
UpdateReport? updateReportOf(Object? v) {
  if (v is! Map<String, Object?> || v.isEmpty) {
    return null;
  }
  return UpdateReport(
    from: v['from'] as String? ?? '',
    to: v['to'] as String? ?? '',
    at: _int(v['at']),
    result: v['result'] as String? ?? '',
    kept: _int(v['kept']),
    added: _int(v['new']),
    gone: _int(v['gone']),
    newKeys: _strings(v['new_keys']),
    goneKeys: _strings(v['gone_keys']),
    reason: v['reason'] as String? ?? '',
    links: _strings(v['links']),
    changesState: v['changes_state'] == true,
    restorePoint: v['restore_point'] == true,
  );
}

/// [p] with the values of `sys/packages/<name>` that move while an update
/// runs (ADR 0048 §1): [value] gives the live value of a leaf (`version`,
/// `latest`, `update_available`, `changes_state`, `state`, `previous`,
/// `last_update`) as plain Dart, or null when none arrived yet.
PackageInfo packageLive(PackageInfo p, Object? Function(String leaf) value) {
  final previous = value('previous');
  final kept = previous is Map<String, Object?> && previous.isNotEmpty
      ? previous
      : null;
  return p.copyWith(
    version: switch (value('version')) {
      final String v when v.isNotEmpty => v,
      _ => p.version,
    },
    latest: value('latest') as String? ?? p.latest,
    updateAvailable: switch (value('update_available')) {
      final bool b => b,
      _ => p.updateAvailable,
    },
    changesState: switch (value('changes_state')) {
      final bool b => b,
      _ => p.changesState,
    },
    state: switch (value('state')) {
      final num n => n.toInt(),
      _ => p.state,
    },
    previous: kept?['version'] as String?,
    keepUntil: _int(kept?['keep_until']),
    previousChangesState: kept?['changes_state'] == true,
    lastUpdate: updateReportOf(value('last_update')),
  );
}

/// `sys/links/<id>/restore_points` (a list as plain Dart), newest first.
List<RestorePoint> restorePointsOf(Object? v) => [
  if (v is List<Object?>)
    for (final e in v)
      if (e is Map<String, Object?>)
        RestorePoint(
          at: _int(e['at']),
          version: e['version'] as String? ?? '',
          size: _int(e['size']),
        ),
];
