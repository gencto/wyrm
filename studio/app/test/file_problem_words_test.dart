import 'package:app/errors.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/studio_error.dart';

/// A file that is no profile is refused with its cause said: which key,
/// which type, where the JSON stops (re-audit of #135, 5), en and uk.
void main() {
  String said(ManifestProblem problem) => wordError(
    StudioError(
      kind: ErrorKind.input,
      hint: ErrorHint.fileNotRead,
      call: 'read',
      thing: 'temp.json',
      fileProblem: problem,
    ),
  ).message;

  const problems = [
    ManifestProblem(fault: ManifestFault.unknownField, field: 'points'),
    ManifestProblem(
      fault: ManifestFault.unknownName,
      field: 'type',
      found: 'colour',
    ),
    ManifestProblem(fault: ManifestFault.notJson, offset: 1),
    ManifestProblem(fault: ManifestFault.notObject),
    ManifestProblem(fault: ManifestFault.wrongForm, field: 'unit'),
    ManifestProblem(fault: ManifestFault.tooDeep),
  ];

  const deepUk = 'temp.json має глибшу вкладеність, ніж дозволено маніфесту.';

  test('each cause is named, en and uk', () async {
    await S.load(const Locale('en'));
    expect(
      [for (final p in problems) said(p)],
      [
        'points is not a field this file has. Nothing was sent.',
        'type: colour is a name this Studio does not know. Nothing was sent.',
        'temp.json is not JSON (at character 1). Nothing was sent.',
        'temp.json is not a JSON object. Nothing was sent.',
        'unit is not of the form it has in a manifest. Nothing was sent.',
        'temp.json nests deeper than a manifest may. Nothing was sent.',
      ],
    );
    await S.load(const Locale('uk'));
    expect(
      [for (final p in problems) said(p)],
      [
        'points — поле, якого цей файл не має. Нічого не надіслано.',
        'type: colour — назва, якої ця Studio не знає. Нічого не надіслано.',
        'temp.json — не JSON (на знаку 1). Нічого не надіслано.',
        'temp.json — не об’єкт JSON. Нічого не надіслано.',
        'unit має не ту форму, яку має в маніфесті. Нічого не надіслано.',
        '$deepUk Нічого не надіслано.',
      ],
    );
    await S.load(const Locale('en'));
  });

  test(
    'a step its plan blocks is said, en and uk (audit 3 of #135, 2)',
    () async {
      String said() => wordError(
        const StudioError(
          kind: ErrorKind.input,
          hint: ErrorHint.stepBlocked,
          call: 'restore_apply',
          key: 'wy/plant/sys/backups',
        ),
      ).message;
      await S.load(const Locale('en'));
      expect(
        said(),
        'This step may not start yet, so nothing was sent. '
        'The dialog says what is missing.',
      );
      await S.load(const Locale('uk'));
      expect(
        said(),
        'Цей крок ще не може початися, тому нічого не надіслано. '
        'Діалог показує, чого бракує.',
      );
      await S.load(const Locale('en'));
    },
  );
}
