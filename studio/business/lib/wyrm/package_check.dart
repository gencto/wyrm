// The check messages read better as one string each.
// ignore_for_file: lines_longer_than_80_chars, cascade_invocations

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:models/package_check.dart';

/// The link protocol of this Studio's brokers (`LINK_PROTOCOL`).
const linkProtocol = 1;

/// What a package check found: the checks, the manifest as indented JSON,
/// and the package name from it.
typedef PackageReport = ({
  List<PackageCheck> checks,
  String? manifest,
  String? name,
  String? kind,
  String? rights,
});

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

PackageCheck _ok(String t, [String d = '']) =>
    PackageCheck(title: t, detail: d);
PackageCheck _bad(String t, String d) =>
    PackageCheck(title: t, detail: d, result: 'failed');
PackageCheck _skip(String t, String d) =>
    PackageCheck(title: t, detail: d, result: 'skipped');

/// The checks of docs/links.md §4 on a package zip, run here before the
/// broker runs them again. [host] is the target broker's `os-arch`, when
/// known.
PackageReport checkZip(Uint8List bytes, {String? host}) {
  final checks = <PackageCheck>[];
  if (bytes.length > 64 << 20) {
    checks.add(
      _bad('Size', '${bytes.length >> 20} MiB zipped; at most 64 MiB'),
    );
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    checks.add(_bad('Archive', 'not a zip'));
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
  }
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    checks.add(_bad('Archive', 'not a zip: $e'));
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
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
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(mf.content));
  } on Object catch (e) {
    checks.add(_bad('Manifest', 'wyrm-link.json is not JSON: $e'));
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
  }
  if (json is! Map<String, Object?>) {
    checks.add(_bad('Manifest', 'wyrm-link.json is not an object'));
    return (
      checks: checks,
      manifest: null,
      name: null,
      kind: null,
      rights: null,
    );
  }
  final pretty = const JsonEncoder.withIndent('  ').convert(json);
  final unknown = json.keys.where((k) => !_fields.contains(k)).toList();
  final name = json['name'];
  final version = json['version'];
  final kind = json['kind'];
  final missing = [
    if (name is! String) 'name',
    if (version is! String) 'version',
    if (json['wyrm_link'] is! int) 'wyrm_link',
    if (kind != 'process' && kind != 'wasm') 'kind',
  ];
  checks.add(
    unknown.isNotEmpty
        ? _bad('Manifest', 'unknown fields: ${unknown.join(', ')}')
        : (missing.isNotEmpty
              ? _bad('Manifest', 'missing or wrong: ${missing.join(', ')}')
              : _ok('Manifest', 'wyrm-link.json')),
  );
  checks.add(
    json['wyrm_link'] == linkProtocol
        ? _ok('Protocol', 'wyrm_link $linkProtocol')
        : _bad(
            'Protocol',
            'wyrm_link ${json['wyrm_link']}; the brokers speak $linkProtocol',
          ),
  );
  if (name is String) {
    checks.add(
      RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(name) &&
              version is String &&
              RegExp(r'^[A-Za-z0-9_+-][A-Za-z0-9._+-]{0,31}$').hasMatch(version)
          ? _ok('Name and version', '$name $version')
          : _bad(
              'Name and version',
              '$name $version: name a key segment, version 1–32 of A–Z a–z 0–9 . _ - +',
            ),
    );
  }
  if (kind == 'process') {
    final entries = json['entries'];
    if (entries is Map<String, Object?> && entries.isNotEmpty) {
      final absent = entries.entries
          .where(
            (e) =>
                e.value is! String || zip.findFile(e.value! as String) == null,
          )
          .map((e) => e.key)
          .toList();
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
      checks.add(_bad('Binaries', 'a process package needs entries per host'));
    }
  } else if (kind == 'wasm') {
    final entry = json['entry'];
    final f = entry is String ? zip.findFile(entry) : null;
    checks.add(
      f == null
          ? _bad('Component', 'entry ${entry ?? '(none)'} not in the zip')
          : (_isWasm(f.content)
                ? _ok('Component', entry! as String)
                : _bad('Component', '$entry is not WebAssembly')),
    );
    checks.add(_skip('World', 'read from the component by the broker'));
  }
  final rights = <String>[
    if (json['capabilities'] case final Map<String, Object?> c) ...[
      if (c['net'] case final List<Object?> n when n.isNotEmpty)
        'network ${n.join(', ')}',
      if (c['store_mb'] case final s?) 'store $s MiB',
      if (c['memory_mb'] case final m?) 'memory $m MiB',
      if (c['call_ms'] case final t?) 'call $t ms',
    ],
    if (json['requester'] case final List<Object?> r)
      for (final g in r)
        if (g case {'path': final p, 'level': final l}) '$l on $p',
  ];
  checks.add(
    rights.isEmpty
        ? _ok('Rights asked', 'none')
        : _ok('Rights asked', rights.join('; ')),
  );
  return (
    checks: checks,
    manifest: pretty,
    name: name is String ? name : null,
    kind: kind is String ? kind : null,
    rights: rights.isEmpty ? null : rights.join('; '),
  );
}

/// The checks of one component file.
PackageReport checkWasm(Uint8List bytes) => (
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
  ],
  manifest: null,
  name: null,
  kind: 'wasm',
  rights: null,
);

/// What Studio reads of a link backup (`.wyrm-link`, ADR 0048 §3.1)
/// before the broker checks all of it: the zip, its `manifest.json`, that
/// it is a link backup, its link (id, driver, mode, package), how its
/// secrets are sealed, and its sections. The grants and the network of the
/// link are in a sealed part: the broker lists them when the install needs
/// `accept`. `name` is the link's id, `kind` its mode.
PackageReport checkBackup(Uint8List bytes) {
  PackageReport stop(List<PackageCheck> checks) =>
      (checks: checks, manifest: null, name: null, kind: null, rights: null);
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
  final Map<String, Object?> m;
  try {
    m = jsonDecode(
      utf8.decode(entry.content as List<int>),
    ) as Map<String, Object?>;
  } on Object catch (e) {
    return stop([...checks, _bad('Manifest', '$e')]);
  }
  final link = m['link'];
  if (m['kind'] != 'link' || link is! Map<String, Object?>) {
    checks.add(
      _bad(
        'Kind',
        'a backup of kind ${m['kind']}: Add a link takes a link backup '
            '(.wyrm-link); a broker backup is restored in System',
      ),
    );
    return stop(checks);
  }
  checks.add(
    _ok(
      'Link',
      '${link['id']} · ${link['mode']} · ${link['driver']} · from '
          '${m['site']} (wyrmd ${m['broker']}, ${m['created']})',
    ),
  );
  final package = link['package'] as String? ?? '';
  final sections = [
    if (m['sections'] case final List<Object?> l)
      for (final s in l)
        if (s is Map<String, Object?>) s['name'] as String? ?? '',
  ];
  if (package.isNotEmpty) {
    checks.add(
      sections.contains('package')
          ? _ok('Package', '$package ${link['version']}, in the file')
          : _skip(
              'Package',
              '$package ${link['version']} is not in the file: the broker '
                  'must have it installed',
            ),
    );
  }
  final how = switch (m['sealed']) {
    final Map<String, Object?> s => s['how'] as String? ?? 'none',
    _ => 'none',
  };
  checks
    ..add(
      switch (how) {
        'passphrase' => _ok('Secrets', 'sealed with a passphrase'),
        'broker' => _skip(
          'Secrets',
          'sealed for ${m['site']}: the file opens only on a broker with '
              'the keys of that site',
        ),
        _ => _ok('Secrets', 'none in the file'),
      },
    )
    ..add(_ok('Sections', sections.join(', ')))
    ..add(
      _skip(
        'Definition, grants, package files',
        'checked by the broker as a new link',
      ),
    );
  return (
    checks: checks,
    manifest: const JsonEncoder.withIndent('  ').convert({
      for (final k in ['wyrm_backup', 'kind', 'site', 'broker', 'created'])
        k: m[k],
      'sealed': how,
      'link': link,
      'sections': sections,
    }),
    name: link['id'] as String?,
    kind: link['mode'] as String?,
    rights: null,
  );
}

/// A URL or a Git repository: fetched and checked by the broker only.
PackageReport checkRemote(String what) => (
  checks: [
    _skip('Download', '$what is fetched by the broker'),
    _skip(
      'Archive, manifest, binaries',
      'checked by the broker after the download',
    ),
  ],
  manifest: null,
  name: null,
  kind: null,
  rights: null,
);

bool _isWasm(List<int> b) =>
    b.length >= 4 && b[0] == 0 && b[1] == 0x61 && b[2] == 0x73 && b[3] == 0x6d;
