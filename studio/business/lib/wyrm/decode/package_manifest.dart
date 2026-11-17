import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/json_value.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_kind.dart';
import 'package:models/requested_right.dart';

import 'decoded.dart';
import 'fields.dart';
import 'requested_rights.dart';

/// One field of a manifest a person wrote, as the check of it needs it:
/// there and of its type, absent, or of another type (with its text, for
/// the line that says so).
sealed class Stated<T> {
  const Stated();

  /// The value when it is there and of its type.
  T? get value => switch (this) {
    Given(:final value) => value,
    Absent() || Wrong() => null,
  };

  /// What the file holds, for a message.
  String get shown => switch (this) {
    Given(:final value) => '$value',
    Absent() => '(none)',
    Wrong(:final text) => text,
  };
}

final class Given<T> extends Stated<T> {
  const Given(this.value);

  @override
  final T value;
}

final class Absent<T> extends Stated<T> {
  const Absent();
}

final class Wrong<T> extends Stated<T> {
  const Wrong(this.text);

  /// The value as the file writes it.
  final String text;
}

Stated<String> _text(JsonValue? v) => switch (v) {
  null || JsonNull() => const Absent(),
  JsonText(:final text) => Given(text),
  _ => Wrong(jsonEncode(v.raw)),
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

/// The manifest of a package (`wyrm-link.json`), read once for the checks
/// of docs/links.md §4: each field the checks look at with its type, so a
/// check says what is wrong with the file instead of reading it again.
final class PackageManifest {
  const PackageManifest({
    required this.pretty,
    required this.unknown,
    required this.name,
    required this.version,
    required this.protocol,
    required this.kind,
    required this.entries,
    required this.entry,
    required this.rights,
  });

  /// The manifest as indented JSON.
  final String pretty;

  /// The fields the format does not have.
  final IList<String> unknown;
  final Stated<String> name;
  final Stated<String> version;

  /// `wyrm_link`.
  final Stated<int> protocol;

  /// `process` or `wasm`; any other name is [Wrong].
  final Stated<PackageKind> kind;

  /// `entries` of a process package: the file of each host (`os-arch`),
  /// null for an entry that is not a text. Null when the manifest has no
  /// map of entries.
  final IMap<String, String?>? entries;

  /// `entry` of a WASM package.
  final Stated<String> entry;

  /// What the package asks for (`capabilities`, `requester`).
  final Decoded<List<RequestedRight>> rights;
}

/// The [PackageManifest] of the bytes of a `wyrm-link.json`. Bytes that
/// are not a JSON object are [Invalid].
Decoded<PackageManifest> packageManifestOf(List<int> bytes) {
  final JsonValue json;
  try {
    json = JsonValue.of(jsonDecode(utf8.decode(bytes)));
  } on Object catch (e) {
    return Invalid('package manifest', '', 'not JSON: $e');
  }
  if (json is! JsonMap) {
    return const Invalid('package manifest', '', 'not an object');
  }
  final f = json.fields;
  return Valid(
    PackageManifest(
      pretty: const JsonEncoder.withIndent('  ').convert(json.raw),
      unknown: f.keys.where((k) => !_fields.contains(k)).toIList(),
      name: _text(f['name']),
      version: _text(f['version']),
      protocol: switch (f['wyrm_link']) {
        null || JsonNull() => const Absent(),
        JsonNumber(value: final int n) => Given(n),
        final other => Wrong(jsonEncode(other.raw)),
      },
      kind: switch (_text(f['kind'])) {
        Given(:final value) => switch (PackageKind.fromWire(value)) {
          final k? => Given(k),
          null => Wrong(value),
        },
        Absent() => const Absent(),
        Wrong(:final text) => Wrong(text),
      },
      entries: switch (f['entries']) {
        JsonMap(:final fields) => {
          for (final MapEntry(:key, :value) in fields.entries)
            key: _text(value).value,
        }.lock,
        _ => null,
      },
      entry: _text(f['entry']),
      rights: requestedRightsOf(f['capabilities']?.raw, f['requester']?.raw),
    ),
  );
}

/// What the `manifest.json` of a backup file says it is.
sealed class BackupManifest {
  const BackupManifest();
}

/// A backup that is not of one link (a broker backup): its `kind`.
final class OtherBackup extends BackupManifest {
  const OtherBackup(this.kind);

  final String kind;
}

/// The manifest of a link backup (`.wyrm-link`, ADR 0048 §3.1, `Manifest`
/// of `wyrm-admin`): what Studio shows of it before the broker checks all
/// of it.
final class LinkBackup extends BackupManifest {
  const LinkBackup({
    required this.format,
    required this.site,
    required this.broker,
    required this.created,
    required this.sealed,
    required this.id,
    required this.driver,
    required this.mode,
    required this.package,
    required this.version,
    required this.sections,
  });

  /// `wyrm_backup`: the version of the format.
  final int format;
  final String site;

  /// The version of the broker that made it.
  final String broker;
  final String created;
  final BackupSealed sealed;

  /// The link: its id, driver and mode, and the package it runs (empty:
  /// a built-in driver) with its version.
  final String id;
  final String driver;
  final LinkMode mode;
  final String package;
  final String version;
  final IList<BackupSection> sections;

  /// The manifest as indented JSON, without its files and seals.
  String get pretty => const JsonEncoder.withIndent('  ').convert({
    'wyrm_backup': format,
    'kind': 'link',
    'site': site,
    'broker': broker,
    'created': created,
    'sealed': sealed.wire,
    'link': {
      'id': id,
      'driver': driver,
      'mode': mode.wire,
      if (package.isNotEmpty) 'package': package,
      if (version.isNotEmpty) 'version': version,
    },
    'sections': [for (final s in sections) s.wire],
  });
}

/// The fields of one JSON object of a manifest, read strictly: the typed
/// value or a [BadField] with the field's path.
extension type const _Json._(({IMap<String, JsonValue> fields, String at}) _) {
  factory _Json.of(JsonValue? v, String at) => switch (v) {
    JsonMap(:final fields) => _Json._((fields: fields, at: at)),
    null || JsonNull() => throw BadField(at, 'missing'),
    _ => throw BadField(at, 'not an object'),
  };

  String _path(String field) => _.at.isEmpty ? field : '${_.at}.$field';

  JsonValue? operator [](String field) => _.fields[field];

  String text(String field) => switch (_.fields[field]) {
    JsonText(:final text) => text,
    null || JsonNull() => throw BadField(_path(field), 'missing'),
    _ => throw BadField(_path(field), 'not a text'),
  };

  String textOr(String field, String absent) => switch (_.fields[field]) {
    null || JsonNull() => absent,
    _ => text(field),
  };

  int whole(String field) => switch (_.fields[field]) {
    JsonNumber(value: final int n) => n,
    null || JsonNull() => throw BadField(_path(field), 'missing'),
    _ => throw BadField(_path(field), 'not a whole number'),
  };

  E name<E>(String field, E? Function(String wire) fromWire) =>
      fromWire(text(field)) ??
      (throw BadField(_path(field), 'not a known name: ${text(field)}'));
}

/// The [BackupManifest] of the bytes of a backup's `manifest.json`. A link
/// backup is read strictly: a field that is missing or of another type, a
/// mode, a seal or a section this client does not know is [Invalid] with
/// its field (the broker refuses such a manifest too).
Decoded<BackupManifest> backupManifestOf(List<int> bytes) {
  final JsonValue json;
  try {
    json = JsonValue.of(jsonDecode(utf8.decode(bytes)));
  } on Object catch (e) {
    return Invalid('backup manifest', '', 'not JSON: $e');
  }
  return decoding('backup manifest', () {
    final m = _Json.of(json, '');
    final kind = m.text('kind');
    if (kind != 'link') {
      return OtherBackup(kind);
    }
    final link = _Json.of(m['link'], 'link');
    final sealed = _Json.of(m['sealed'], 'sealed');
    final sections = switch (m['sections']) {
      JsonList(:final items) => [
        for (final s in items)
          _Json.of(s, 'sections').name('name', BackupSection.fromWire),
      ],
      _ => throw const BadField('sections', 'not an array'),
    };
    return LinkBackup(
      format: m.whole('wyrm_backup'),
      site: m.text('site'),
      broker: m.text('broker'),
      created: m.text('created'),
      sealed: sealed.name('how', BackupSealed.fromWire),
      id: link.text('id'),
      driver: link.text('driver'),
      mode: link.name('mode', LinkMode.fromWire),
      package: link.textOr('package', ''),
      version: link.textOr('version', ''),
      sections: sections.lock,
    );
  });
}
