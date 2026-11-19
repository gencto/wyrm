import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_link_facts.dart';
import 'package:models/backup_manifest.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/json_value.dart';
import 'package:models/link_mode.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/package_kind.dart';
import 'package:models/package_manifest.dart';
import 'package:models/package_manifest_read.dart';
import 'package:models/stated.dart';

import 'decoded.dart';
import 'requested_rights.dart';

// The manifests a person brings, read once: a package's `wyrm-link.json`
// and a backup's `manifest.json`. What is wrong with one is a typed
// [ManifestProblem] (a kind and the field): `ui` says it, in the language
// on screen; nothing here is worded for a person.

Stated<String> _text(JsonValue? v) => switch (v) {
  null || JsonNull() => const Stated.absent(),
  JsonText(:final text) => Stated.given(text),
  _ => Stated.wrong(jsonEncode(v.raw)),
};

/// The fields of `wyrm-link.json` (docs/links.md §4).
const _fields = {
  'name',
  'version',
  'description',
  'wyrm_link',
  'kind',
  'entries',
  'args',
  'requester',
  'entry',
  'world',
  'capabilities',
};

/// The JSON of [bytes]; bytes that are not JSON, or that nest deeper than
/// a manifest may, throw a [_Bad]. The parser's own words go to the log
/// only: what is shown is the typed fault.
JsonValue _jsonOf(List<int> bytes) {
  final Object? parsed;
  try {
    parsed = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    decodeLog.fine('manifest: not JSON: ${e.message}');
    throw _Bad(ManifestFault.notJson, '', offset: e.offset);
  }
  try {
    return JsonValue.of(parsed);
  } on JsonTooDeep {
    throw const _Bad(ManifestFault.tooDeep, '');
  }
}

/// The [PackageManifest] of the bytes of a `wyrm-link.json`, or why they
/// are none: not JSON, or JSON that is no object.
PackageManifestRead packageManifestOf(List<int> bytes) {
  final JsonValue json;
  try {
    json = _jsonOf(bytes);
  } on _Bad catch (b) {
    return PackageManifestRead.unreadable(
      b.problem,
    );
  }
  if (json is! JsonMap) {
    return const PackageManifestRead.unreadable(
      ManifestProblem(fault: ManifestFault.notObject),
    );
  }
  final f = json.fields;
  final rights = requestedRightsOf(f['capabilities']?.raw, f['requester']?.raw);
  return PackageManifestRead.read(
    PackageManifest(
      pretty: const JsonEncoder.withIndent('  ').convert(json.raw),
      unknown: f.keys.where((k) => !_fields.contains(k)).toIList(),
      name: _text(f['name']),
      version: _text(f['version']),
      protocol: switch (f['wyrm_link']) {
        null || JsonNull() => const Stated.absent(),
        JsonNumber(value: final int n) => Stated.given(n),
        final other => Stated.wrong(jsonEncode(other.raw)),
      },
      kind: switch (_text(f['kind'])) {
        StatedGiven(:final value) => switch (PackageKind.fromWire(value)) {
          final k? => Stated.given(k),
          null => Stated.wrong(value),
        },
        StatedAbsent() => const Stated.absent(),
        StatedWrong(:final text) => Stated.wrong(text),
      },
      entries: switch (f['entries']) {
        JsonMap(:final fields) => {
          for (final MapEntry(:key, :value) in fields.entries)
            key: _text(value).orNull,
        }.lock,
        _ => null,
      },
      entry: _text(f['entry']),
      rights: switch (rights) {
        Valid(:final value) => value.lock,
        Invalid() => const IListConst([]),
      },
      rightsProblem: switch (rights) {
        Valid() => null,
        // the field of the manifest that is not of its form
        Invalid(:final field) => ManifestProblem(
          fault: ManifestFault.wrongForm,
          field: field,
        ),
      },
    ),
  );
}

/// A field of a backup's manifest that is not of its form.
final class _Bad implements Exception {
  const _Bad(this.fault, this.field, {this.found, this.offset});

  final ManifestFault fault;
  final String field;

  /// The name the file holds, when it is one Studio does not know.
  final String? found;

  /// Where the bytes stop being JSON.
  final int? offset;

  ManifestProblem get problem => ManifestProblem(
    fault: fault,
    field: field,
    found: found,
    offset: offset,
  );
}

/// The fields of one JSON object of a manifest, read strictly: the typed
/// value or a [_Bad] with the field's path.
final class _Json {
  const _Json._(this._fields, this._at);

  factory _Json.of(JsonValue? v, String at) => switch (v) {
    JsonMap(:final fields) => _Json._(fields, at),
    null || JsonNull() => throw _Bad(ManifestFault.missing, at),
    _ => throw _Bad(
      at.isEmpty ? ManifestFault.notObject : ManifestFault.wrongForm,
      at,
    ),
  };

  final IMap<String, JsonValue> _fields;

  /// The path of this object in the file; empty for the file itself.
  final String _at;

  String _path(String field) => _at.isEmpty ? field : '$_at.$field';

  JsonValue? operator [](String field) => _fields[field];

  String text(String field) => switch (_fields[field]) {
    JsonText(:final text) => text,
    null || JsonNull() => throw _Bad(ManifestFault.missing, _path(field)),
    _ => throw _Bad(ManifestFault.wrongForm, _path(field)),
  };

  String textOr(String field, String absent) => switch (_fields[field]) {
    null || JsonNull() => absent,
    _ => text(field),
  };

  int whole(String field) => switch (_fields[field]) {
    JsonNumber(value: final int n) => n,
    null || JsonNull() => throw _Bad(ManifestFault.missing, _path(field)),
    _ => throw _Bad(ManifestFault.wrongForm, _path(field)),
  };

  /// An RFC 3339 time.
  DateTime moment(String field) =>
      DateTime.tryParse(text(field)) ??
      (throw _Bad(ManifestFault.wrongForm, _path(field)));

  E name<E>(String field, E? Function(String wire) fromWire) =>
      fromWire(text(field)) ??
      (throw _Bad(
        ManifestFault.unknownName,
        _path(field),
        found: text(field),
      ));
}

/// The [BackupManifest] of the bytes of a backup's `manifest.json`. A link
/// backup is read strictly: a field that is missing or of another form, a
/// mode, a seal or a section this client does not know makes it
/// [UnreadableBackupManifest] with the field (the broker refuses such a
/// manifest too).
BackupManifest backupManifestOf(List<int> bytes) {
  try {
    final m = _Json.of(_jsonOf(bytes), '');
    final kind = m.text('kind');
    if (kind != 'link') {
      return BackupManifest.other(kind);
    }
    final link = _Json.of(m['link'], 'link');
    final sealed = _Json.of(m['sealed'], 'sealed');
    final sections = switch (m['sections']) {
      JsonList(:final items) => [
        for (final s in items)
          _Json.of(s, 'sections').name('name', BackupSection.fromWire),
      ],
      null || JsonNull() => throw const _Bad(ManifestFault.missing, 'sections'),
      _ => throw const _Bad(ManifestFault.wrongForm, 'sections'),
    };
    final how = sealed.name('how', BackupSealed.fromWire);
    return BackupManifest.link(
      format: m.whole('wyrm_backup'),
      link: BackupLinkFacts(
        id: link.text('id'),
        mode: link.name('mode', LinkMode.fromWire),
        driver: link.text('driver'),
        site: m.text('site'),
        broker: m.text('broker'),
        created: m.moment('created'),
      ),
      sealed: how,
      package: link.textOr('package', ''),
      version: link.textOr('version', ''),
      sections: sections.lock,
      pretty: const JsonEncoder.withIndent('  ').convert({
        'wyrm_backup': m.whole('wyrm_backup'),
        'kind': kind,
        'site': m.text('site'),
        'broker': m.text('broker'),
        'created': m.text('created'),
        'sealed': how.wire,
        'link': m['link']?.raw,
        'sections': [for (final s in sections) s.wire],
      }),
    );
  } on _Bad catch (b) {
    return BackupManifest.unreadable(
      b.problem,
    );
  }
}
