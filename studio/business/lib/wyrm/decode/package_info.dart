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
/// [PackageInfo]. Each attribute is decoded on its own: one of another
/// type, or a kind this client does not know, is left at its default
/// **and logged** with its field and [where].
PackageInfo packageInfoOf(String name, NodeMeta m, {required String where}) {
  String? text(String f) => switch (m.attr?[f]) {
    null || VNull() => null,
    VStr(:final v) => v,
    _ => Invalid<String>(_package, f, 'not a text').orWarn(where),
  };
  return PackageInfo(
    name: name,
    version: text('version') ?? '',
    kind: switch (text('kind')) {
      null => PackageKind.process,
      final w =>
        PackageKind.fromWire(w) ??
            const Invalid<PackageKind>(
              _package,
              'kind',
              'not a known kind',
            ).orWarn(where) ??
            PackageKind.process,
    },
    source: text('source'),
    sha256: text('sha256'),
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
/// none arrived yet (the meta's stays). Each leaf is decoded on its own:
/// one of another shape is left out **and logged** with its name and
/// [where]; the others stay.
PackageInfo packageLiveOf(
  PackageInfo p,
  Object? Function(String leaf) value, {
  required String where,
}) {
  T? ok<T>(Decoded<T?> d) => d.orWarn(where);
  final kept = switch (value('previous')) {
    null => null,
    final Map<Object?, Object?> m when m.isEmpty => null,
    final Map<Object?, Object?> m => {
      for (final e in m.entries) '${e.key}': e.value,
    },
    _ => ok(
      const Invalid<Map<String, Object?>>(_package, 'previous', 'not a map'),
    ),
  };
  return p.copyWith(
    version: switch (ok(liveText(value('version'), _package, 'version'))) {
      final s? when s.isNotEmpty => s,
      _ => p.version,
    },
    latest: ok(liveText(value('latest'), _package, 'latest')) ?? p.latest,
    updateAvailable:
        ok(_bool(value('update_available'), 'update_available')) ??
        p.updateAvailable,
    changesState:
        ok(_bool(value('changes_state'), 'changes_state')) ?? p.changesState,
    state: ok(liveInt(value('state'), _package, 'state')) ?? p.state,
    previous: ok(liveText(kept?['version'], _package, 'previous.version')),
    keepUntil:
        ok(liveInt(kept?['keep_until'], _package, 'previous.keep_until')) ?? 0,
    previousChangesState:
        ok(_bool(kept?['changes_state'], 'previous.changes_state')) ?? false,
    lastUpdate: ok(updateReportOf(value('last_update'), where: where)),
  );
}

Decoded<bool?> _bool(Object? v, String field) => switch (v) {
  null => const Valid(null),
  final bool b => Valid(b),
  _ => Invalid(_package, field, 'not a bool'),
};

/// `sys/packages/<name>/last_update` (a map as plain Dart, or the wire
/// value of a read) as an [UpdateReport]; none for the empty map of a
/// package never updated, or no value; [Invalid] when it is no map.
///
/// Each field is read on its own: one of another type is left at its
/// default **and logged** with its field and [where]; a `result` this
/// client does not know is [UpdateResult.unknown] with the broker's word,
/// never a dropped report.
Decoded<UpdateReport?> updateReportOf(Object? v, {required String where}) {
  final Map<String, Object?> m;
  switch (v) {
    case null || VNull():
      return const Valid(null);
    case final Value wire:
      return updateReportOf(_plain(wire), where: where);
    case final Map<Object?, Object?> map:
      m = {for (final e in map.entries) '${e.key}': e.value};
    default:
      return const Invalid(_report, '', 'not a map');
  }
  if (m.isEmpty) {
    return const Valid(null);
  }
  T? warned<T>(String field, String reason) =>
      Invalid<T>(_report, field, reason).orWarn(where);
  String text(String f) => switch (m[f]) {
    null => '',
    final String s => s,
    _ => warned<String>(f, 'not a text') ?? '',
  };
  int count(String f) => liveInt(m[f], _report, f).orWarn(where) ?? 0;
  IList<String> texts(String f) => switch (m[f]) {
    null => const IListConst([]),
    final List<Object?> l => [
      for (final e in l)
        if (e is String) e else ?warned<String>(f, 'not a text in the list'),
    ].lock,
    _ => warned<IList<String>>(f, 'not a list') ?? const IListConst([]),
  };
  bool flag(String f) => switch (m[f]) {
    null => false,
    final bool b => b,
    _ => warned<bool>(f, 'not a bool') ?? false,
  };
  final word = text('result');
  final result = switch (word) {
    '' => null,
    final w =>
      UpdateResult.fromWire(w) ??
          (warned<UpdateResult>('result', 'not a known result') ??
              UpdateResult.unknown),
  };
  return Valid(
    UpdateReport(
      from: text('from'),
      to: text('to'),
      at: count('at'),
      result: result,
      resultWord: word,
      kept: count('kept'),
      added: count('new'),
      gone: count('gone'),
      newKeys: texts('new_keys'),
      goneKeys: texts('gone_keys'),
      reason: text('reason'),
      links: texts('links'),
      changesState: flag('changes_state'),
      restorePoint: flag('restore_point'),
    ),
  );
}

/// `sys/links/<id>/restore_points` (a list as plain Dart): its rows, in
/// the broker's order; none when no value arrived; [Invalid] when it is no
/// list. A row that is not one is left out, the others stay.
///
/// With [where] each row left out is recorded with it: the place the
/// value arrives at passes it (`warnUnreadLive`, a one-shot read). A
/// selector reads the same value on every rebuild and passes none: it
/// records nothing.
Decoded<List<RestorePoint>> restorePointsOf(Object? v, {String? where}) {
  if (v == null) {
    return const Valid([]);
  }
  if (v is! List<Object?>) {
    return const Invalid(_points, '', 'not a list');
  }
  T? take<T>(Decoded<T> d) => where == null ? d.orNull : d.orWarn(where);
  final points = <RestorePoint>[];
  for (final e in v) {
    if (e is! Map<Object?, Object?>) {
      take(const Invalid<RestorePoint>(_points, '', 'a row is not a map'));
      continue;
    }
    final at = take(liveInt(e['at'], _points, 'at'));
    final size = take(liveInt(e['size'], _points, 'size'));
    final version = liveText(e['version'], _points, 'version');
    if (at == null || size == null || version is Invalid) {
      take(version);
      continue;
    }
    points.add(
      RestorePoint(
        at: at,
        version: (version as Valid<String?>).value ?? '',
        size: size,
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
