import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/pages/link_install_data.dart';

/// What is wrong with a manifest, and the link of a link backup, are said
/// here from typed values, in the language on screen.
void main() {
  InstallCheckVm problem(
    ManifestFaultKind kind, {
    String field = '',
    String? found,
  }) => InstallCheckVm(
    title: 'Manifest',
    result: CheckResult.failed,
    problem: ManifestProblemVm(
      kind: kind,
      file: 'manifest.json',
      field: field,
      found: found,
    ),
  );

  test('every kind of fault has its sentence, en and uk', () async {
    await S.load(const Locale('en'));
    expect(
      [
        problem(ManifestFaultKind.notJson).row.detail,
        problem(ManifestFaultKind.notObject).row.detail,
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
        'link.mode має не ту форму, яку має в маніфесті',
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
      title: 'Link',
      result: CheckResult.ok,
      link: BackupLinkVm(
        id: 'meter',
        mode: LinkRunMode.process,
        driver: 'pkg:acme-meter',
        site: 'plant',
        broker: '0.1.0',
        created: made,
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
}
