import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/package_info.dart';
import 'package:models/package_kind.dart';
import 'package:models/restore_point.dart';
import 'package:models/update_report.dart';
import 'package:models/update_result.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'live_fields.dart';

const _package = 'package';
const _report = 'last update';
const _points = 'restore points';

/// The full `~meta` of `sys/packages/<name>` (`wy:package`) as a
/// [PackageInfo]; a field of another type, or a kind this client does not
/// know, is [Invalid] with its field.
Decoded<PackageInfo> packageInfoOf(String name, NodeMeta m) {
  final texts = <String, String?>{};
  for (final f in ['version', 'kind', 'source', 'sha256']) {
    switch (m.attr?[f]) {
      case null || VNull():
        texts[f] = null;
      case VStr(:final v):
        texts[f] = v;
      default:
        return Invalid(_package, f, 'not a text');
    }
  }
  final kind = switch (texts['kind']) {
    null => PackageKind.process,
    final w => PackageKind.fromWire(w),
  };
  if (kind == null) {
    return const Invalid(_package, 'kind', 'not a known kind');
  }
  return Valid(
    PackageInfo(
      name: name,
      version: texts['version'] ?? '',
      kind: kind,
      source: texts['source'],
      sha256: texts['sha256'],
    ),
  );
}

/// The leaves of `sys/packages/<name>` that move while an update runs
/// (ADR 0048 §1), as [packageLiveOf] reads them.
const packageLeaves = [
  'version',
  'latest',
  'update_available',
  'changes_state',
  'state',
  'previous',
  'last_update',
];

/// [p] with the live values of `sys/packages/<name>`: [value] gives the
/// live value of a leaf of [packageLeaves] as plain Dart, or null when
/// none arrived yet (the meta's stays). A leaf of another shape is
/// [Invalid] with its name.
Decoded<PackageInfo> packageLiveOf(
  PackageInfo p,
  Object? Function(String leaf) value,
) {
  final Map<String, Object?>? kept;
  switch (value('previous')) {
    case null:
      kept = null;
    case final Map<Object?, Object?> m:
      kept = m.isEmpty
          ? null
          : {for (final e in m.entries) '${e.key}': e.value};
    default:
      return const Invalid(_package, 'previous', 'not a map');
  }
  final report = updateReportOf(value('last_update'));
  final UpdateReport? last;
  switch (report) {
    case Valid(:final value):
      last = value;
    case Invalid(:final field, :final reason):
      return Invalid(_package, 'last_update.$field', reason);
  }
  final version = liveText(value('version'), _package, 'version');
  final latest = liveText(value('latest'), _package, 'latest');
  final available = _bool(value('update_available'), 'update_available');
  final changes = _bool(value('changes_state'), 'changes_state');
  final format = liveInt(value('state'), _package, 'state');
  final previous = liveText(kept?['version'], _package, 'previous.version');
  final until = liveInt(kept?['keep_until'], _package, 'previous.keep_until');
  final back = _bool(kept?['changes_state'], 'previous.changes_state');
  for (final d in <Decoded<Object?>>[
    version,
    latest,
    available,
    changes,
    format,
    previous,
    until,
    back,
  ]) {
    if (d case Invalid(:final field, :final reason)) {
      return Invalid(_package, field, reason);
    }
  }
  T? v<T>(Decoded<T?> d) => (d as Valid<T?>).value;
  return Valid(
    p.copyWith(
      version: switch (v(version)) {
        final s? when s.isNotEmpty => s,
        _ => p.version,
      },
      latest: v(latest) ?? p.latest,
      updateAvailable: v(available) ?? p.updateAvailable,
      changesState: v(changes) ?? p.changesState,
      state: v(format) ?? p.state,
      previous: v(previous),
      keepUntil: v(until) ?? 0,
      previousChangesState: v(back) ?? false,
      lastUpdate: last,
    ),
  );
}

Decoded<bool?> _bool(Object? v, String field) => switch (v) {
  null => const Valid(null),
  final bool b => Valid(b),
  _ => Invalid(_package, field, 'not a bool'),
};

/// `sys/packages/<name>/last_update` (a map as plain Dart, or the wire
/// value of a read) as an [UpdateReport]; none for the empty map of a
/// package never updated, or no value.
Decoded<UpdateReport?> updateReportOf(Object? v) {
  final Map<String, Object?> m;
  switch (v) {
    case null || VNull():
      return const Valid(null);
    case final Value wire:
      return updateReportOf(_plain(wire));
    case final Map<Object?, Object?> map:
      m = {for (final e in map.entries) '${e.key}': e.value};
    default:
      return const Invalid(_report, '', 'not a map');
  }
  if (m.isEmpty) {
    return const Valid(null);
  }
  final texts = <String, String>{};
  for (final f in ['from', 'to', 'result', 'reason']) {
    switch (m[f]) {
      case null:
        texts[f] = '';
      case final String s:
        texts[f] = s;
      default:
        return Invalid(_report, f, 'not a text');
    }
  }
  final counts = <String, int>{};
  for (final f in ['at', 'kept', 'new', 'gone']) {
    switch (liveInt(m[f], _report, f)) {
      case Valid(:final value):
        counts[f] = value ?? 0;
      case final Invalid<int?> i:
        return Invalid(_report, i.field, i.reason);
    }
  }
  final lists = <String, IList<String>>{};
  for (final f in ['new_keys', 'gone_keys', 'links']) {
    switch (m[f]) {
      case null:
        lists[f] = const IListConst([]);
      case final List<Object?> l when l.every((e) => e is String):
        lists[f] = l.cast<String>().lock;
      default:
        return Invalid(_report, f, 'not a list of texts');
    }
  }
  final flags = <String, bool>{};
  for (final f in ['changes_state', 'restore_point']) {
    switch (m[f]) {
      case null:
        flags[f] = false;
      case final bool b:
        flags[f] = b;
      default:
        return Invalid(_report, f, 'not a bool');
    }
  }
  final result = switch (texts['result']!) {
    '' => null,
    final w => UpdateResult.fromWire(w),
  };
  if (result == null && texts['result']!.isNotEmpty) {
    return const Invalid(_report, 'result', 'not a known result');
  }
  return Valid(
    UpdateReport(
      from: texts['from']!,
      to: texts['to']!,
      at: counts['at']!,
      result: result,
      kept: counts['kept']!,
      added: counts['new']!,
      gone: counts['gone']!,
      newKeys: lists['new_keys']!,
      goneKeys: lists['gone_keys']!,
      reason: texts['reason']!,
      links: lists['links']!,
      changesState: flags['changes_state']!,
      restorePoint: flags['restore_point']!,
    ),
  );
}

/// `sys/links/<id>/restore_points` (a list as plain Dart): its rows, in
/// the broker's order; none when no value arrived.
Decoded<List<RestorePoint>> restorePointsOf(Object? v) {
  if (v == null) {
    return const Valid([]);
  }
  if (v is! List<Object?>) {
    return const Invalid(_points, '', 'not a list');
  }
  final points = <RestorePoint>[];
  for (final e in v) {
    if (e is! Map<Object?, Object?>) {
      return const Invalid(_points, '', 'a row is not a map');
    }
    final at = liveInt(e['at'], _points, 'at');
    final size = liveInt(e['size'], _points, 'size');
    final version = liveText(e['version'], _points, 'version');
    for (final d in <Decoded<Object?>>[at, size, version]) {
      if (d case Invalid(:final field, :final reason)) {
        return Invalid(_points, field, reason);
      }
    }
    points.add(
      RestorePoint(
        at: (at as Valid<int?>).value ?? 0,
        version: (version as Valid<String?>).value ?? '',
        size: (size as Valid<int?>).value ?? 0,
      ),
    );
  }
  return Valid(points);
}

/// A wire value read once (not through the live values service) as the
/// plain Dart the live values hold.
Object? _plain(Value v) => switch (v) {
  VNull() => null,
  VBool(:final v) => v,
  VInt(:final v) => v,
  VFloat(:final v) => v,
  VStr(:final v) => v,
  VBytes(:final v) => v,
  VArray(:final v) => [for (final e in v) _plain(e)],
  VMap(:final v) => {for (final e in v.entries) e.key: _plain(e.value)},
};
