import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:business/wyrm/catalog.dart';
import 'package:business/wyrm/package_check.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/link_mode.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_finding.dart';
import 'package:models/requested_right.dart';
import 'package:wyrm_client/wyrm_client.dart';

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
    test('a manifest that is no JSON object is a typed problem', () {
      for (final (text, fault) in [
        ('{', ManifestFault.notJson),
        ('[1, 2]', ManifestFault.notObject),
      ]) {
        final a = Archive()
          ..addFile(ArchiveFile.string('wyrm-link.json', text));
        final r = checkZip(Uint8List.fromList(ZipEncoder().encode(a)));
        final c = r.checks.last;
        expect(c.result, PackageCheckResult.failed, reason: text);
        // a typed finding: nothing is said in words here
        final f = c.finding as FindingManifestProblem;
        expect(f.problem.fault, fault, reason: text);
        expect(f.file, 'wyrm-link.json');
      }
    });

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

      expect(
        r.checks.where((c) => c.result == PackageCheckResult.failed),
        isEmpty,
      );
      expect(r.name, 'acme-meter');
      expect(r.kind, LinkMode.process);
      expect(r.rights, [
        const RequestedRight.grant(
          level: Perm.read,
          path: 'wy/{site}/downstream/modbus',
        ),
      ]);
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

      final failed = [
        for (final c in r.checks.where(
          (c) => c.result == PackageCheckResult.failed,
        ))
          c.finding,
      ];
      // the manifest, the protocol and this host, each with its facts
      expect(
        failed,
        containsAll([
          PackageFinding.unknownFields(const ['colour'].lock),
          const PackageFinding.protocol(found: '2', speak: 1, matches: false),
          const PackageFinding.host('linux-x86_64', present: false),
        ]),
      );
    });

    test('a path out of the archive fails', () {
      final r = checkZip(
        zipOf({
          '../evil': [0],
          'wyrm-link.json': json({}),
        }),
      );
      expect(
        r.checks.firstWhere((c) => c.finding is FindingPathNotRelative),
        const PackageCheck(
          PackageFinding.pathNotRelative('../evil'),
          result: PackageCheckResult.failed,
        ),
      );
    });

    test('not a zip, or no manifest, stops early', () {
      expect(
        checkZip(Uint8List.fromList([1, 2, 3])).checks.single,
        const PackageCheck(
          PackageFinding.notZip(),
          result: PackageCheckResult.failed,
        ),
      );
      expect(
        checkZip(
          zipOf({
            'readme': [0],
          }),
        ).checks.last,
        const PackageCheck(
          PackageFinding.noManifest('wyrm-link.json'),
          result: PackageCheckResult.failed,
        ),
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

      expect(
        r.checks.firstWhere((c) => c.finding is FindingComponent),
        const PackageCheck(
          PackageFinding.component(entry: 'reg.wasm', found: true, wasm: true),
        ),
      );
      // the rights are a finding too, said by ui
      expect(
        r.checks.last.finding,
        PackageFinding.rights(
          const [
            RequestedRight.network(['10.0.5.0/24:502']),
            RequestedRight.store(1),
          ].lock,
        ),
      );
      expect(r.rights, const [
        RequestedRight.network(['10.0.5.0/24:502']),
        RequestedRight.store(1),
      ]);
    });
  });

  group('the other checks, as facts', () {
    test('a file too large, a component that is none, a missing one', () {
      expect(
        checkWasm(Uint8List.fromList([1, 2, 3])).checks,
        const [
          PackageCheck(PackageFinding.size(kib: 1)),
          PackageCheck(
            PackageFinding.component(entry: null, found: true, wasm: false),
            result: PackageCheckResult.failed,
          ),
          PackageCheck(
            PackageFinding.worldByBroker(),
            result: PackageCheckResult.skipped,
          ),
        ],
      );
      final noEntry = checkZip(
        zipOf({
          'wyrm-link.json': json({
            'name': 'reg',
            'version': '1.0.0',
            'wyrm_link': 1,
            'kind': 'wasm',
            'entry': 'reg.wasm',
          }),
        }),
      );
      expect(
        noEntry.checks.firstWhere((c) => c.finding is FindingComponent),
        const PackageCheck(
          PackageFinding.component(
            entry: 'reg.wasm',
            found: false,
            wasm: false,
          ),
          result: PackageCheckResult.failed,
        ),
      );
    });

    test('missing fields, a name of another form, binaries not there', () {
      final r = checkZip(
        zipOf({
          'wyrm-link.json': json({
            'name': 'bad name',
            'kind': 'process',
            'entries': {'linux-aarch64': 'bin/none'},
          }),
        }),
      );
      expect(
        [for (final c in r.checks) c.finding],
        containsAll([
          PackageFinding.missingFields(const ['version', 'wyrm_link'].lock),
          const PackageFinding.protocol(found: null, speak: 1, matches: false),
          const PackageFinding.nameVersion(
            name: 'bad name',
            version: null,
            ok: false,
          ),
          PackageFinding.entryMissing(const ['linux-aarch64'].lock),
        ]),
      );
      expect(
        checkZip(
          zipOf({
            'wyrm-link.json': json({
              'name': 'x',
              'version': '1',
              'wyrm_link': 1,
              'kind': 'process',
            }),
          }),
        ).checks.map((c) => c.finding),
        contains(const PackageFinding.needsEntries()),
      );
    });

    test('what the broker alone checks', () {
      expect(
        checkRemote('https://example.org/x.zip').checks.map((c) => c.finding),
        const [
          PackageFinding.fetchedByBroker('https://example.org/x.zip'),
          PackageFinding.checkedAfterDownload(),
        ],
      );
      // a source that names no address says so by a value, not a word
      expect(
        checkRemote(null).checks.first.finding,
        const PackageFinding.fetchedByBroker(null),
      );
      expect(
        checkLargeBackup(80 << 20).checks.single,
        const PackageCheck(
          PackageFinding.notReadHere(mib: 80),
          result: PackageCheckResult.skipped,
        ),
      );
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
    expect(c[0].modes, [
      LinkMode.embedded,
      LinkMode.process,
      LinkMode.external,
    ]);
    expect(
      c[1].modes,
      [LinkMode.embedded],
      reason: 'the agent runs in the broker',
    );
    expect(c[2].modes, [LinkMode.wasm]);
    expect(c[2].existing, 1);
    expect(c[3].modes, [LinkMode.process]);
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

  group('attr.catalog (ADR 0043 §7)', () {
    Value row(
      String id, {
      String title = '',
      String summary = '',
      String category = '',
      String version = '',
      String form = '',
      bool official = false,
    }) => Value.from({
      'id': id,
      'code': id.split(':').last,
      'link': '',
      'title': title,
      'summary': summary,
      'category': category,
      'version': version,
      'form': form,
      'official': official,
    });

    test("no attr.catalog: no rows, today's behaviour", () {
      expect(catalogRowsOf(null), isNull);
      expect(catalogRowsOf({'other': Value.from(1)}), isNull);
      final old = catalogOf(
        drivers: ['modbus'],
        packages: ['alarm'],
        rows: catalogRowsOf({}),
      );
      expect(old[1].name, 'Alarms', reason: 'Studio keeps its own names');
      expect(old.map((i) => i.official), everyElement(isFalse));
    });

    test('rows give title, summary, category, version and the mark', () {
      final rows = catalogRowsOf({
        'catalog': Value.from([
          row(
            'driver:modbus',
            title: 'Modbus',
            summary: 'TCP and RTU',
            category: 'Protocols',
            version: '0.2.0',
            form: 'builtin',
            official: true,
          ),
          row(
            'package:alarm-process',
            title: 'Alarms',
            summary: 'Alarm classes',
            category: 'Apps',
            version: '0.1.3',
            form: 'process',
            official: true,
          ),
          row('package:telegram', version: '1.0.0', form: 'wasm'),
        ]),
      })!;
      final c = catalogOf(
        drivers: ['modbus', 'mock'],
        packages: ['alarm-process', 'telegram'],
        brokerVersion: '0.1.0',
        rows: rows,
      );
      final modbus = c[0];
      expect(modbus.name, 'Modbus');
      expect(modbus.description, 'TCP and RTU');
      expect(modbus.category, 'Protocols');
      expect(modbus.version, 'wyrmd 0.2.0', reason: "the row's version wins");
      expect(modbus.official, isTrue);
      // A driver with no row keeps Studio's text and the broker version.
      expect(c[1].name, 'Mock');
      expect(c[1].version, 'wyrmd 0.1.0');
      expect(c[1].official, isFalse);
      final alarm = c[2];
      expect(alarm.name, 'Alarms (process)');
      expect(alarm.modes, [LinkMode.process]);
      expect(alarm.version, '0.1.3');
      expect(alarm.official, isTrue);
      // A package with empty fields reads its own name, never Studio's.
      final tg = c[3];
      expect(tg.name, 'telegram');
      expect(tg.description, '');
      expect(tg.category, 'Packages', reason: 'no empty category chip');
      expect(tg.version, '1.0.0');
      expect(tg.modes, [LinkMode.wasm]);
      expect(tg.official, isFalse);
    });

    test('a package of another repository borrows no official text', () {
      final c = catalogOf(
        drivers: const [],
        packages: ['modbus', 'alarm'],
        rows: catalogRowsOf({
          'catalog': Value.from([
            row('package:modbus', title: 'My Modbus', form: 'wasm'),
          ]),
        }),
      );
      expect(c[0].name, 'My Modbus');
      expect(c[0].description, '', reason: 'not the built-in driver text');
      expect(c[0].tag, 'MODB', reason: 'its own tag, not the official one');
      expect(c[0].official, isFalse);
      // No row for it: its name only, the choices still list it.
      expect(c[1].name, 'alarm');
      expect(c[1].category, 'Packages');
    });

    test('rows only describe: the choices decide what is listed', () {
      final c = catalogOf(
        drivers: ['modbus', 'wasm'],
        packages: const [],
        rows: catalogRowsOf({
          'catalog': Value.from([
            row('driver:wasm', title: 'WASM host', official: true),
            row('driver:s7', title: 'Siemens S7', official: true),
          ]),
        }),
      );
      expect(c.map((i) => i.code), ['modbus']);
    });

    test('the rows survive the wire: a sys/links ~meta through CBOR', () {
      // As the broker sends it: the choices of `install` and `install_repo`
      // and `attr.catalog`, an array of maps (ADR 0043 §7).
      final sent = NodeMeta(
        attr: {
          'catalog': Value.from([
            {
              'id': 'driver:modbus',
              'code': 'modbus',
              'link': 'modbus',
              'title': 'Modbus',
              'summary': 'TCP and RTU',
              'category': 'Equipment',
              'version': '0.3.0',
              'form': 'builtin',
              'official': true,
            },
            {
              'id': 'package:alarm',
              'code': 'alarm',
              'link': 'alarm',
              'title': 'Alarms',
              'summary': 'Alarm classes',
              'category': 'Apps',
              'version': '0.1.2',
              'form': 'wasm',
              'official': true,
            },
          ]),
        },
        actions: {
          'install': ActionMeta(
            params: {
              'driver': ParamMeta(enumValues: ['modbus']),
            },
          ),
          'install_repo': ActionMeta(
            params: {
              'package': ParamMeta(enumValues: ['alarm']),
            },
          ),
        },
      );
      final got = NodeMeta.fromCbor(sent.toCbor());
      List<String> choices(String a, String p) =>
          got.actions?[a]?.params[p]?.enumValues ?? const [];
      final c = catalogOf(
        drivers: choices('install', 'driver'),
        packages: choices('install_repo', 'package'),
        brokerVersion: '0.3.0',
        rows: catalogRowsOf(got.attr),
      );
      expect(
        [for (final i in c) (i.name, i.version, i.official)],
        [
          ('Modbus', 'wyrmd 0.3.0', true),
          ('Alarms', '0.1.2', true),
        ],
      );
    });
  });
}
