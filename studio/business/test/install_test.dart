import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:business/wyrm/catalog.dart';
import 'package:business/wyrm/package_check.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List zipOf(Map<String, List<int>> files) {
  final a = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    a.addFile(ArchiveFile.bytes(key, value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

List<int> json(Object o) => utf8.encode(jsonEncode(o));

void main() {
  group('checkZip', () {
    test('a process package for this host passes and reports its rights', () {
      final r = checkZip(
        zipOf({
          'wyrm-link.json': json({
            'name': 'acme-meter',
            'version': '1.2.0',
            'wyrm_link': 1,
            'kind': 'process',
            'entries': {'linux-aarch64': 'bin/acme'},
            'requester': [
              {'path': 'wy/{site}/downstream/modbus', 'level': 'read'},
            ],
          }),
          'bin/acme': [1, 2, 3],
        }),
        host: 'linux-aarch64',
      );

      expect(r.checks.where((c) => c.result == 'failed'), isEmpty);
      expect(r.name, 'acme-meter');
      expect(r.kind, 'process');
      expect(r.rights, 'read on wy/{site}/downstream/modbus');
      expect(r.manifest, contains('"wyrm_link": 1'));
    });

    test('no entry for the host, a bad protocol and unknown fields fail', () {
      final r = checkZip(
        zipOf({
          'wyrm-link.json': json({
            'name': 'x',
            'version': '1',
            'wyrm_link': 2,
            'kind': 'process',
            'entries': {'macos-aarch64': 'bin/x'},
            'colour': 'red',
          }),
          'bin/x': [0],
        }),
        host: 'linux-x86_64',
      );

      final failed = {
        for (final c in r.checks.where((c) => c.result == 'failed')) c.title,
      };
      expect(failed, containsAll(['Manifest', 'Protocol', 'This host']));
    });

    test('a path out of the archive fails', () {
      final r = checkZip(
        zipOf({
          '../evil': [0],
          'wyrm-link.json': json({}),
        }),
      );
      expect(
        r.checks.firstWhere((c) => c.title == 'Paths').result,
        'failed',
      );
    });

    test('not a zip, or no manifest, stops early', () {
      expect(
        checkZip(Uint8List.fromList([1, 2, 3])).checks.single.result,
        'failed',
      );
      expect(
        checkZip(
          zipOf({
            'readme': [0],
          }),
        ).checks.last.detail,
        contains('no wyrm-link.json'),
      );
    });

    test('a wasm package needs its component', () {
      final r = checkZip(
        zipOf({
          'wyrm-link.json': json({
            'name': 'reg',
            'version': '1.0.0',
            'wyrm_link': 1,
            'kind': 'wasm',
            'entry': 'reg.wasm',
            'capabilities': {
              'net': ['10.0.5.0/24:502'],
              'store_mb': 1,
            },
          }),
          'reg.wasm': [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0],
        }),
      );

      expect(r.checks.firstWhere((c) => c.title == 'Component').result, 'ok');
      expect(r.rights, 'network 10.0.5.0/24:502; store 1 MiB');
    });
  });

  test('catalogOf: drivers, packages, existing links', () {
    final c = catalogOf(
      drivers: ['modbus', 'agent', 'wasm'],
      packages: ['postgres', 'scheduler-process'],
      existing: {'modbus': 2, 'pkg:postgres': 1},
    );

    expect(c.map((i) => i.id), [
      'driver:modbus',
      'driver:agent',
      'package:postgres',
      'package:scheduler-process',
    ]);
    expect(c[0].existing, 2);
    expect(c[0].modes, ['embedded', 'process', 'external']);
    expect(c[1].modes, ['embedded'], reason: 'the agent runs in the broker');
    expect(c[2].modes, ['wasm']);
    expect(c[2].existing, 1);
    expect(c[3].modes, ['process']);
    expect(c[3].name, 'Scheduler (process)');
    expect(c.map((i) => i.version), everyElement(isNull));
  });

  test('catalogOf: a driver carries the broker version, a package none', () {
    final c = catalogOf(
      drivers: ['modbus'],
      packages: ['postgres'],
      brokerVersion: '0.1.0',
    );
    expect(c[0].version, 'wyrmd 0.1.0');
    // `install_repo` lists package names only: no version to show.
    expect(c[1].version, isNull);
  });
}
