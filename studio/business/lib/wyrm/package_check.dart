// The check messages read better as one string each.
// ignore_for_file: lines_longer_than_80_chars, cascade_invocations

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_kind.dart';
import 'package:models/package_report.dart';
import 'package:models/requested_right.dart';

import 'decode/decoded.dart';
import 'decode/package_manifest.dart';

/// The link protocol of this Studio's brokers (`LINK_PROTOCOL`).
const linkProtocol = 1;

PackageCheck _ok(String t, [String d = '']) =>
    PackageCheck(title: t, detail: d);
PackageCheck _bad(String t, String d) =>
    PackageCheck(title: t, detail: d, result: PackageCheckResult.failed);
PackageCheck _skip(String t, String d) =>
    PackageCheck(title: t, detail: d, result: PackageCheckResult.skipped);

/// The checks of docs/links.md §4 on a package zip, run here before the
/// broker runs them again. [host] is the target broker's `os-arch`, when
/// known.
PackageReport checkZip(Uint8List bytes, {String? host}) {
  final checks = <PackageCheck>[];
  if (bytes.length > 64 << 20) {
    checks.add(
      _bad('Size', '${bytes.length >> 20} MiB zipped; at most 64 MiB'),
    );
    return PackageReport(checks: checks.lock);
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    checks.add(_bad('Archive', 'not a zip'));
    return PackageReport(checks: checks.lock);
  }
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    checks.add(_bad('Archive', 'not a zip: $e'));
    return PackageReport(checks: checks.lock);
  }
  final files = zip.files.where((f) => f.isFile).toList();
  final unpacked = files.fold<int>(0, (n, f) => n + f.size);
  checks.add(
    files.length > 1000 || unpacked > 256 << 20
        ? _bad(
            'Size and files',
            '${files.length} files, ${unpacked >> 20} MiB unpacked; at most 1000 and 256 MiB',
          )
        : _ok(
            'Size and files',
            '${(bytes.length / 1024).ceil()} KiB, ${files.length} files',
          ),
  );
  final badPath = zip.files
      .map((f) => f.name)
      .where(
        (n) =>
            n.startsWith('/') ||
            n.split('/').contains('..') ||
            n.contains(r'\'),
      )
      .firstOrNull;
  final link = zip.files.where((f) => f.isSymbolicLink).firstOrNull;
  checks.add(
    badPath != null
        ? _bad('Paths', 'not relative: $badPath')
        : (link != null
              ? _bad('Paths', 'symbolic link: ${link.name}')
              : _ok('Paths', 'relative, no links')),
  );
  final mf = zip.findFile('wyrm-link.json');
  if (mf == null) {
    checks.add(_bad('Manifest', 'no wyrm-link.json at the zip root'));
    return PackageReport(checks: checks.lock);
  }
  final PackageManifest m;
  switch (packageManifestOf(mf.content)) {
    case Valid(:final value):
      m = value;
    case Invalid(:final reason):
      checks.add(_bad('Manifest', 'wyrm-link.json is $reason'));
      return PackageReport(checks: checks.lock);
  }
  final name = m.name.value;
  final version = m.version.value;
  final kind = m.kind.value;
  final missing = [
    if (name == null) 'name',
    if (version == null) 'version',
    if (m.protocol.value == null) 'wyrm_link',
    if (kind == null) 'kind',
  ];
  checks.add(
    m.unknown.isNotEmpty
        ? _bad('Manifest', 'unknown fields: ${m.unknown.join(', ')}')
        : (missing.isNotEmpty
              ? _bad('Manifest', 'missing or wrong: ${missing.join(', ')}')
              : _ok('Manifest', 'wyrm-link.json')),
  );
  checks.add(
    m.protocol.value == linkProtocol
        ? _ok('Protocol', 'wyrm_link $linkProtocol')
        : _bad(
            'Protocol',
            'wyrm_link ${m.protocol.shown}; the brokers speak $linkProtocol',
          ),
  );
  if (name != null) {
    checks.add(
      RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(name) &&
              version != null &&
              RegExp(r'^[A-Za-z0-9_+-][A-Za-z0-9._+-]{0,31}$').hasMatch(version)
          ? _ok('Name and version', '$name $version')
          : _bad(
              'Name and version',
              '$name ${m.version.shown}: name a key segment, version 1–32 of A–Z a–z 0–9 . _ - +',
            ),
    );
  }
  switch (kind) {
    case PackageKind.process:
      final entries = m.entries;
      if (entries != null && entries.isNotEmpty) {
        final absent = [
          for (final MapEntry(:key, :value) in entries.entries)
            if (value == null || zip.findFile(value) == null) key,
        ];
        checks.add(
          absent.isNotEmpty
              ? _bad('Binaries', 'entry file missing for ${absent.join(', ')}')
              : _ok('Binaries', entries.keys.join(', ')),
        );
        if (host != null) {
          checks.add(
            entries.containsKey(host)
                ? _ok('This host', host)
                : _bad('This host', 'no entry for $host'),
          );
        }
      } else {
        checks.add(
          _bad('Binaries', 'a process package needs entries per host'),
        );
      }
    case PackageKind.wasm:
      final entry = m.entry.value;
      final f = entry == null ? null : zip.findFile(entry);
      checks.add(
        f == null || entry == null
            ? _bad('Component', 'entry ${m.entry.shown} not in the zip')
            : (_isWasm(f.content)
                  ? _ok('Component', entry)
                  : _bad('Component', '$entry is not WebAssembly')),
      );
      checks.add(_skip('World', 'read from the component by the broker'));
    case null:
      break;
  }
  final List<RequestedRight> rights;
  switch (m.rights) {
    case Valid(:final value):
      rights = value;
      // the rights themselves: ui says them in the language on screen
      checks.add(PackageCheck(title: 'Rights asked', rights: rights.lock));
    case Invalid(:final field, :final reason):
      rights = const [];
      checks.add(_bad('Rights asked', '$field: $reason'));
  }
  return PackageReport(
    checks: checks.lock,
    manifest: m.pretty,
    name: name,
    kind: switch (kind) {
      PackageKind.process => LinkMode.process,
      PackageKind.wasm => LinkMode.wasm,
      null => null,
    },
    rights: rights.isEmpty ? null : rights.lock,
  );
}

/// The checks of one component file.
PackageReport checkWasm(Uint8List bytes) => PackageReport(
  checks: [
    if (bytes.length > 64 << 20)
      _bad('Size', '${bytes.length >> 20} MiB; at most 64 MiB')
    else
      _ok('Size', '${(bytes.length / 1024).ceil()} KiB'),
    if (_isWasm(bytes))
      _ok('Component', 'WebAssembly')
    else
      _bad('Component', 'not WebAssembly'),
    _skip('World', 'read from the component by the broker'),
  ].lock,
  kind: LinkMode.wasm,
);

/// What Studio reads of a link backup (`.wyrm-link`, ADR 0048 §3.1)
/// before the broker checks all of it: the zip, its `manifest.json`, that
/// it is a link backup, its link (id, driver, mode, package), how its
/// secrets are sealed, and its sections. The grants and the network of the
/// link are in a sealed part: the broker lists them when the install needs
/// `accept`. `name` is the link's id, `kind` its mode.
PackageReport checkBackup(Uint8List bytes) {
  PackageReport stop(List<PackageCheck> checks) =>
      PackageReport(checks: checks.lock);
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    return stop([_bad('Archive', 'not a zip')]);
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    return stop([_bad('Archive', '$e')]);
  }
  final checks = <PackageCheck>[
    _ok('Archive', '${archive.files.length} entries'),
  ];
  final entry = archive.findFile('manifest.json');
  if (entry == null) {
    return stop([...checks, _bad('Manifest', 'no manifest.json')]);
  }
  final LinkBackup m;
  switch (backupManifestOf(entry.content)) {
    case Valid(value: final LinkBackup link):
      m = link;
    case Valid(value: OtherBackup(:final kind)):
      checks.add(
        _bad(
          'Kind',
          'a backup of kind $kind: Add a link takes a link backup '
              '(.wyrm-link); a broker backup is restored in System',
        ),
      );
      return stop(checks);
    // a manifest Studio cannot read fails the check with its field: a
    // seal, a mode or a section it does not know is never taken as one
    // it knows
    case Invalid(:final field, :final reason):
      return stop([
        ...checks,
        _bad('Manifest', field.isEmpty ? reason : '$field: $reason'),
      ]);
  }
  checks.add(
    _ok(
      'Link',
      '${m.id} · ${m.mode.wire} · ${m.driver} · from '
          '${m.site} (wyrmd ${m.broker}, ${m.created})',
    ),
  );
  if (m.package.isNotEmpty) {
    checks.add(
      m.sections.contains(BackupSection.package)
          ? _ok('Package', '${m.package} ${m.version}, in the file')
          : _skip(
              'Package',
              '${m.package} ${m.version} is not in the file: the broker '
                  'must have it installed',
            ),
    );
  }
  checks
    ..add(
      switch (m.sealed) {
        BackupSealed.passphrase => _ok('Secrets', 'sealed with a passphrase'),
        BackupSealed.broker => _skip(
          'Secrets',
          'sealed for ${m.site}: the file opens only on a broker with '
              'the keys of that site',
        ),
        BackupSealed.none => _ok('Secrets', 'none in the file'),
      },
    )
    ..add(_ok('Sections', [for (final s in m.sections) s.wire].join(', ')))
    ..add(
      _skip(
        'Definition, grants, package files',
        'checked by the broker as a new link',
      ),
    );
  return PackageReport(
    checks: checks.lock,
    manifest: m.pretty,
    name: m.id,
    kind: m.mode,
  );
}

/// A link backup too large to read here: the broker alone checks it.
PackageReport checkLargeBackup(int size) => PackageReport(
  checks: [
    _skip(
      'Archive, manifest, link',
      '${size >> 20} MiB: not read by Studio; checked by the broker after '
          'the upload. Give the link its name on the next step',
    ),
  ].lock,
);

/// A URL or a Git repository: fetched and checked by the broker only.
PackageReport checkRemote(String what) => PackageReport(
  checks: [
    _skip('Download', '$what is fetched by the broker'),
    _skip(
      'Archive, manifest, binaries',
      'checked by the broker after the download',
    ),
  ].lock,
);

bool _isWasm(List<int> b) =>
    b.length >= 4 && b[0] == 0 && b[1] == 0x61 && b[2] == 0x73 && b[3] == 0x6d;
