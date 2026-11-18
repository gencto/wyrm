import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/pages/install_checks.dart';
import 'package:ui/pages/link_install_data.dart';

/// The rights a package asks for are said in one place, `ui`, in the
/// language on screen: on the rights card and in the check that lists
/// them.
void main() {
  const rights = [
    NetworkRightVm(['10.0.5.0/24:502']),
    SizeRightVm(1, store: true),
    SizeRightVm(64, store: false),
    CallRightVm(200),
    GrantRightVm(AccessLevel.read, 'wy/{site}/downstream/modbus'),
  ];

  test('en', () async {
    await S.load(const Locale('en'));
    expect(
      [for (final r in rights) r.line],
      [
        'network 10.0.5.0/24:502',
        'store 1 MiB',
        'memory 64 MiB',
        'call 200 ms',
        'read on wy/{site}/downstream/modbus',
      ],
    );
    const check = InstallCheckVm(
      finding: RightsFinding([]),
      result: CheckResult.ok,
    );
    expect(check.row.detail, 'none');
  });

  test('uk', () async {
    await S.load(const Locale('uk'));
    expect(
      [for (final r in rights) r.line],
      [
        'мережа 10.0.5.0/24:502',
        'сховище 1 MiB',
        'пам’ять 64 MiB',
        'виклик 200 мс',
        'читання на wy/{site}/downstream/modbus',
      ],
    );
    const check = InstallCheckVm(
      finding: RightsFinding(rights),
      result: CheckResult.ok,
    );
    expect(check.row.detail, startsWith('мережа 10.0.5.0/24:502; сховище'));
  });
}
