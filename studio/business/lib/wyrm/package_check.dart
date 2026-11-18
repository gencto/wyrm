import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_manifest.dart';
import 'package:models/backup_section.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_finding.dart';
import 'package:models/package_kind.dart';
import 'package:models/package_manifest.dart';
import 'package:models/package_manifest_read.dart';
import 'package:models/package_report.dart';

import 'decode/decoded.dart';
import 'decode/package_manifest.dart';

// The checks of docs/links.md §4, run here before the broker runs them
// again. Each check is a typed finding ([PackageFinding]) with its
// result: nothing in this file is worded for a person; `ui` names the
// check and says what it found.

/// The link protocol of this Studio's brokers (`LINK_PROTOCOL`).
const linkProtocol = 1;

/// The limits of a package (docs/links.md §4).
const _maxZipMib = 64;
const _maxFiles = 1000;
const _maxUnpackedMib = 256;

/// The manifests by their names in the archive.
const _packageManifest = 'wyrm-link.json';
const _backupManifest = 'manifest.json';

PackageCheck _ok(PackageFinding f) => PackageCheck(f);
PackageCheck _bad(PackageFinding f) =>
    PackageCheck(f, result: PackageCheckResult.failed);
PackageCheck _skip(PackageFinding f) =>
    PackageCheck(f, result: PackageCheckResult.skipped);

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

/// The checks on a package zip. [host] is the target broker's `os-arch`,
/// when known.
PackageReport checkZip(Uint8List bytes, {String? host}) {
  final checks = <PackageCheck>[];
  PackageReport stop() => PackageReport(checks: checks.lock);
  if (bytes.length > _maxZipMib << 20) {
    checks.add(
      _bad(
        PackageFinding.tooLarge(
          mib: bytes.length >> 20,
          limitMib: _maxZipMib,
          zipped: true,
        ),
      ),
    );
    return stop();
  }
  if (!_isZip(bytes)) {
    checks.add(_bad(const PackageFinding.notZip()));
    return stop();
  }
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    decodeLog.fine('package: not a zip: $e');
    checks.add(_bad(const PackageFinding.notZip()));
    return stop();
  }
  final files = zip.files.where((f) => f.isFile).toList();
  final unpacked = files.fold<int>(0, (n, f) => n + f.size);
  checks.add(
    files.length > _maxFiles || unpacked > _maxUnpackedMib << 20
        ? _bad(
            PackageFinding.tooManyFiles(
              files: files.length,
              mib: unpacked >> 20,
              maxFiles: _maxFiles,
              maxMib: _maxUnpackedMib,
            ),
          )
        : _ok(
            PackageFinding.sizeAndFiles(
              kib: (bytes.length / 1024).ceil(),
              files: files.length,
            ),
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
        ? _bad(PackageFinding.pathNotRelative(badPath))
        : (link != null
              ? _bad(PackageFinding.symbolicLink(link.name))
              : _ok(const PackageFinding.pathsOk())),
  );
  final mf = zip.findFile(_packageManifest);
  if (mf == null) {
    checks.add(_bad(const PackageFinding.noManifest(_packageManifest)));
    return stop();
  }
  final PackageManifest m;
  switch (packageManifestOf(mf.content)) {
    case PackageManifestWasRead(:final manifest):
      m = manifest;
    case PackageManifestUnreadable(:final problem):
      checks.add(
        _bad(PackageFinding.manifestProblem(problem, _packageManifest)),
      );
      return stop();
  }
  final name = m.name.orNull;
  final version = m.version.orNull;
  final kind = m.kind.orNull;
  // the fields by their names in the file
  final missing = [
    if (name == null) 'name',
    if (version == null) 'version',
    if (m.protocol.orNull == null) 'wyrm_link',
    if (kind == null) 'kind',
  ];
  checks
    ..add(
      m.unknown.isNotEmpty
          ? _bad(PackageFinding.unknownFields(m.unknown))
          : (missing.isNotEmpty
                ? _bad(PackageFinding.missingFields(missing.lock))
                : _ok(const PackageFinding.manifestOk(_packageManifest))),
    )
    ..add(
      PackageCheck(
        PackageFinding.protocol(
          found: m.protocol.written,
          speak: linkProtocol,
          matches: m.protocol.orNull == linkProtocol,
        ),
        result: m.protocol.orNull == linkProtocol
            ? PackageCheckResult.ok
            : PackageCheckResult.failed,
      ),
    );
  if (name != null) {
    final ok =
        RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(name) &&
        version != null &&
        RegExp(r'^[A-Za-z0-9_+-][A-Za-z0-9._+-]{0,31}$').hasMatch(version);
    checks.add(
      PackageCheck(
        PackageFinding.nameVersion(
          name: name,
          version: m.version.written,
          ok: ok,
        ),
        result: ok ? PackageCheckResult.ok : PackageCheckResult.failed,
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
              ? _bad(PackageFinding.entryMissing(absent.lock))
              : _ok(PackageFinding.hosts(entries.keys.toIList())),
        );
        if (host != null) {
          final present = entries.containsKey(host);
          checks.add(
            PackageCheck(
              PackageFinding.host(host, present: present),
              result: present
                  ? PackageCheckResult.ok
                  : PackageCheckResult.failed,
            ),
          );
        }
      } else {
        checks.add(_bad(const PackageFinding.needsEntries()));
      }
    case PackageKind.wasm:
      final entry = m.entry.orNull;
      final f = entry == null ? null : zip.findFile(entry);
      final wasm = f != null && _isWasm(f.content);
      checks
        ..add(
          PackageCheck(
            PackageFinding.component(
              entry: f == null ? m.entry.written : entry,
              found: f != null,
              wasm: wasm,
            ),
            result: wasm ? PackageCheckResult.ok : PackageCheckResult.failed,
          ),
        )
        ..add(_skip(const PackageFinding.worldByBroker()));
    case null:
      break;
  }
  final rights = m.rights;
  checks.add(
    switch (m.rightsProblem) {
      null => _ok(PackageFinding.rights(rights)),
      final problem => _bad(
        PackageFinding.rightsProblem(problem, _packageManifest),
      ),
    },
  );
  return PackageReport(
    checks: checks.lock,
    manifest: m.pretty,
    name: name,
    kind: switch (kind) {
      PackageKind.process => LinkMode.process,
      PackageKind.wasm => LinkMode.wasm,
      null => null,
    },
    rights: rights.isEmpty ? null : rights,
  );
}

/// The checks of one component file.
PackageReport checkWasm(Uint8List bytes) {
  final wasm = _isWasm(bytes);
  return PackageReport(
    checks: [
      if (bytes.length > _maxZipMib << 20)
        _bad(
          PackageFinding.tooLarge(
            mib: bytes.length >> 20,
            limitMib: _maxZipMib,
            zipped: false,
          ),
        )
      else
        _ok(PackageFinding.size(kib: (bytes.length / 1024).ceil())),
      PackageCheck(
        PackageFinding.component(entry: null, found: true, wasm: wasm),
        result: wasm ? PackageCheckResult.ok : PackageCheckResult.failed,
      ),
      _skip(const PackageFinding.worldByBroker()),
    ].lock,
    kind: LinkMode.wasm,
  );
}

/// What Studio reads of a link backup (`.wyrm-link`, ADR 0048 §3.1)
/// before the broker checks all of it: the zip, its `manifest.json`, that
/// it is a link backup, its link (id, driver, mode, package), how its
/// secrets are sealed, and its sections. The grants and the network of the
/// link are in a sealed part: the broker lists them when the install needs
/// `accept`. `name` is the link's id, `kind` its mode.
PackageReport checkBackup(Uint8List bytes) {
  PackageReport stop(List<PackageCheck> checks) =>
      PackageReport(checks: checks.lock);
  if (!_isZip(bytes)) {
    return stop([_bad(const PackageFinding.notZip())]);
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    decodeLog.fine('backup: not a zip: $e');
    return stop([_bad(const PackageFinding.notZip())]);
  }
  final checks = <PackageCheck>[
    _ok(PackageFinding.archiveEntries(archive.files.length)),
  ];
  final entry = archive.findFile(_backupManifest);
  if (entry == null) {
    return stop([
      ...checks,
      _bad(const PackageFinding.noManifest(_backupManifest)),
    ]);
  }
  final LinkBackupManifest m;
  switch (backupManifestOf(entry.content)) {
    case final LinkBackupManifest link:
      m = link;
    case OtherBackupManifest(:final kind):
      return stop([...checks, _bad(PackageFinding.otherKind(kind))]);
    // a manifest Studio cannot read fails the check with a typed problem:
    // a seal, a mode or a section it does not know is never taken as one
    // it knows
    case UnreadableBackupManifest(:final problem):
      return stop([
        ...checks,
        _bad(PackageFinding.manifestProblem(problem, _backupManifest)),
      ]);
  }
  checks.add(_ok(PackageFinding.link(m.link)));
  if (m.package.isNotEmpty) {
    final inFile = m.sections.contains(BackupSection.package);
    checks.add(
      PackageCheck(
        PackageFinding.packageOfLink(
          name: m.package,
          version: m.version,
          inFile: inFile,
        ),
        // not in the file: the broker must have it installed
        result: inFile ? PackageCheckResult.ok : PackageCheckResult.skipped,
      ),
    );
  }
  checks
    ..add(
      PackageCheck(
        PackageFinding.secrets(m.sealed, m.link.site),
        // sealed for its site: whether it opens is known on the broker
        result: switch (m.sealed) {
          .broker => PackageCheckResult.skipped,
          .passphrase || .none => PackageCheckResult.ok,
        },
      ),
    )
    ..add(_ok(PackageFinding.sections(m.sections)))
    ..add(_skip(const PackageFinding.checkedAsNewLink()));
  return PackageReport(
    checks: checks.lock,
    manifest: m.pretty,
    name: m.link.id,
    kind: m.link.mode,
  );
}

/// A link backup too large to read here: the broker alone checks it.
PackageReport checkLargeBackup(int size) => PackageReport(
  checks: [_skip(PackageFinding.notReadHere(mib: size >> 20))].lock,
);

/// A URL or a Git repository ([what]: its address, null when the source
/// names none): fetched and checked by the broker only.
PackageReport checkRemote(String? what) => PackageReport(
  checks: [
    _skip(PackageFinding.fetchedByBroker(what)),
    _skip(const PackageFinding.checkedAfterDownload()),
  ].lock,
);

bool _isWasm(List<int> b) =>
    b.length >= 4 && b[0] == 0 && b[1] == 0x61 && b[2] == 0x73 && b[3] == 0x6d;
