// The expected sentences read better as one string each.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/overlays/backup_data.dart';
import 'package:ui/pages/install_checks.dart';
import 'package:ui/pages/link_install_data.dart';

/// What is wrong with a manifest, and the link of a link backup, are said
/// here from typed values, in the language on screen.
void main() {
  InstallCheckVm problem(
    ManifestFaultKind kind, {
    String field = '',
    String? found,
  }) => InstallCheckVm(
    finding: ManifestProblemFinding(
      ManifestProblemVm(
        kind: kind,
        file: 'manifest.json',
        field: field,
        found: found,
      ),
    ),
    result: CheckResult.failed,
  );

  test('every kind of fault has its sentence, en and uk', () async {
    await S.load(const Locale('en'));
    expect(
      [
        problem(ManifestFaultKind.notJson).row.detail,
        problem(ManifestFaultKind.notObject).row.detail,
        const InstallCheckVm(
          finding: ManifestProblemFinding(
            ManifestProblemVm(
              kind: ManifestFaultKind.notJson,
              file: 'manifest.json',
              offset: 17,
            ),
          ),
          result: CheckResult.failed,
        ).row.detail,
        problem(ManifestFaultKind.tooDeep).row.detail,
        problem(ManifestFaultKind.unknownField, field: 'colour').row.detail,
        problem(ManifestFaultKind.missing, field: 'link.id').row.detail,
        problem(ManifestFaultKind.wrongForm, field: 'sections').row.detail,
        problem(
          ManifestFaultKind.unknownName,
          field: 'sealed.how',
          found: 'hsm',
        ).row.detail,
      ],
      [
        'manifest.json is not JSON',
        'manifest.json is not a JSON object',
        // the cause is said: where the JSON stops, which field is not one
        'manifest.json is not JSON (at character 17)',
        'manifest.json nests deeper than a manifest may',
        'colour is not a field this file has',
        'link.id is missing',
        'sections is not of the form it has in a manifest',
        'sealed.how: hsm is a name this Studio does not know',
      ],
    );

    await S.load(const Locale('uk'));
    expect(
      [
        for (final k in ManifestFaultKind.values)
          problem(k, field: 'link.mode', found: 'container').row.detail,
      ],
      [
        'manifest.json — не JSON',
        'manifest.json має глибшу вкладеність, ніж дозволено маніфесту',
        'link.mode має не ту форму, яку має в маніфесті',
        'link.mode — поле, якого цей файл не має',
        'немає link.mode',
        'link.mode має не ту форму, яку має в маніфесті',
        'link.mode: container — назва, якої ця Studio не знає',
      ],
    );
  });

  test('the link of a backup: its mode by its label, its time local', () async {
    await S.load(const Locale('en'));
    final made = DateTime.utc(2026, 11, 12, 1);
    final row = InstallCheckVm(
      result: CheckResult.ok,
      finding: LinkFinding(
        BackupLinkVm(
          id: 'meter',
          mode: LinkRunMode.process,
          driver: 'pkg:acme-meter',
          site: 'plant',
          broker: '0.1.0',
          created: made,
        ),
      ),
    ).row;
    expect(
      row.detail,
      'meter · ${LinkRunMode.process.label} · pkg:acme-meter · from plant '
      '(wyrmd 0.1.0, ${Formats.dateTime(made)})',
    );
    // never the wire name of the mode
    expect(row.detail, isNot(contains('· process ·')));
  });

  test('every check has its name and its sentence, en and uk', () async {
    const findings = <CheckFinding>[
      TooLargeFinding(mib: 80, limitMib: 64, zipped: true),
      TooLargeFinding(mib: 80, limitMib: 64, zipped: false),
      NotZipFinding(),
      TooManyFilesFinding(files: 1200, mib: 300, maxFiles: 1000, maxMib: 256),
      SizeAndFilesFinding(kib: 12, files: 3),
      SizeFinding(kib: 12),
      ArchiveEntriesFinding(2),
      PathsFinding(notRelative: '../evil'),
      PathsFinding(symbolicLink: 'lnk'),
      PathsFinding(),
      NoManifestFinding('wyrm-link.json'),
      ManifestFieldsFinding(['colour'], unknown: true),
      ManifestFieldsFinding(['name', 'kind'], unknown: false),
      ManifestOkFinding('wyrm-link.json'),
      ProtocolFinding(found: '1', speak: 1, matches: true),
      ProtocolFinding(found: '2', speak: 1, matches: false),
      ProtocolFinding(found: null, speak: 1, matches: false),
      NameVersionFinding(name: 'acme', version: '1.2.0', ok: true),
      NameVersionFinding(name: 'bad name', version: null, ok: false),
      BinariesFinding(hosts: ['linux-aarch64', 'macos-aarch64']),
      BinariesFinding(missing: ['linux-aarch64']),
      BinariesFinding(),
      HostFinding('linux-aarch64', present: true),
      HostFinding('linux-x86_64', present: false),
      ComponentFinding(entry: 'reg.wasm', found: true, wasm: true),
      ComponentFinding(entry: null, found: true, wasm: true),
      ComponentFinding(entry: 'reg.wasm', found: true, wasm: false),
      ComponentFinding(entry: null, found: true, wasm: false),
      ComponentFinding(entry: 'reg.wasm', found: false, wasm: false),
      WorldByBrokerFinding(),
      RightsFinding([]),
      OtherKindFinding('broker'),
      PackageOfLinkFinding(name: 'modbus', version: '0.5.0', inFile: true),
      PackageOfLinkFinding(name: 'modbus', version: '0.5.0', inFile: false),
      SecretsFinding(BackupSeal.passphrase, 'plant'),
      SecretsFinding(BackupSeal.broker, 'plant'),
      SecretsFinding(BackupSeal.none, 'plant'),
      SectionsFinding([BackupPart.settings, BackupPart.package]),
      CheckedAsNewLinkFinding(),
      NotReadHereFinding(mib: 80),
      FetchedByBrokerFinding('https://example.org/x.zip'),
      FetchedByBrokerFinding(null),
      CheckedAfterDownloadFinding(),
    ];
    await S.load(const Locale('en'));
    final en = [for (final f in findings) '${f.title}: ${f.line}'];
    expect(en, [
      'Size: 80 MiB zipped; at most 64 MiB',
      'Size: 80 MiB; at most 64 MiB',
      'Archive: not a zip',
      'Size and files: 1200 files, 300 MiB unpacked; at most 1000 and 256 MiB',
      'Size and files: 12 KiB, 3 files',
      'Size: 12 KiB',
      'Archive: 2 entries',
      'Paths: not relative: ../evil',
      'Paths: symbolic link: lnk',
      'Paths: relative, no links',
      'Manifest: no wyrm-link.json at the root of the archive',
      'Manifest: unknown fields: colour',
      'Manifest: missing or wrong: name, kind',
      'Manifest: wyrm-link.json',
      'Protocol: wyrm_link 1',
      'Protocol: wyrm_link 2; the brokers speak 1',
      'Protocol: wyrm_link (none); the brokers speak 1',
      'Name and version: acme 1.2.0',
      'Name and version: bad name (none): name a key segment, version 1–32 of A–Z a–z 0–9 . _ - +',
      'Binaries: linux-aarch64, macos-aarch64',
      'Binaries: entry file missing for linux-aarch64',
      'Binaries: a process package needs entries per host',
      'This host: linux-aarch64',
      'This host: no entry for linux-x86_64',
      'Component: reg.wasm',
      'Component: WebAssembly',
      'Component: reg.wasm is not WebAssembly',
      'Component: not WebAssembly',
      'Component: entry reg.wasm not in the zip',
      'World: read from the component by the broker',
      'Rights asked: none',
      'Kind: a backup of kind broker: Add a link takes a link backup (.wyrm-link); a broker backup is restored in System',
      'Package: modbus 0.5.0, in the file',
      'Package: modbus 0.5.0 is not in the file: the broker must have it installed',
      'Secrets: sealed with a passphrase',
      'Secrets: sealed for plant: the file opens only on a broker with the keys of that site',
      'Secrets: none in the file',
      'Sections: ${BackupPart.settings.label}, ${BackupPart.package.label}',
      'Definition, grants, package files: checked by the broker as a new link',
      'Archive, manifest, link: 80 MiB: not read by Studio; checked by the broker after the upload. Give the link its name on the next step',
      'Download: https://example.org/x.zip is fetched by the broker',
      'Download: it is fetched by the broker',
      'Archive, manifest, binaries: checked by the broker after the download',
    ]);

    await S.load(const Locale('uk'));
    final uk = [for (final f in findings) '${f.title}: ${f.line}'];
    expect(uk, hasLength(en.length));
    // every check is named and said in Ukrainian: none keeps its English
    for (final (i, line) in uk.indexed) {
      const same = {
        // a size, a file name, a host and a technical name are no words
        'Component: reg.wasm',
        'Component: WebAssembly',
      };
      if (!same.contains(en[i])) {
        expect(line, isNot(en[i]), reason: en[i]);
      }
    }
    expect(uk.first, 'Розмір: 80 MiB у zip; не більше ніж 64 MiB');
    expect(uk[2], 'Архів: це не zip');
    expect(uk[34], 'Секрети: запечатано паролем');
  });
}
