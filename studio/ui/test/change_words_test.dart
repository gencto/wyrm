import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/models/change_words.dart';

/// The sides of a staged change and the lines of a step-up are said by
/// `ui` from the `.arb` files (studio-rules §5): in English the words
/// `business` used to write, in Ukrainian their translation. A value or a
/// name is data and stays as it came.
void main() {
  setUp(() => S.load(const Locale('en')));

  test('a side of a change reads as the review card always had it', () {
    expect(const ChangeSideVm.text('500 ms').text, '500 ms');
    expect(const ChangeSideVm.none().text, '—');
    expect(const ChangeSideVm.rev(3).text, 'rev 3');
    const was = ChangeSideVm.params([
      ParamSideVm('require_approval', value: 'write'),
      ParamSideVm('allowed_prefixes', list: ['A', 'B']),
      ParamSideVm('emptied', list: []),
      ParamSideVm('unset'),
    ], rev: 2);
    expect(
      was.text,
      'rev 2: require_approval write; allowed_prefixes A, B; emptied []; '
      'unset —',
    );
    expect(
      const ChangeSideVm.params([
        ParamSideVm('require_approval', value: 'config'),
      ]).text,
      'require_approval config',
    );
    expect(const ChangeSideVm.flag(on: true).text, 'on');
    expect(const ChangeSideVm.flag(on: false).text, 'off');
    expect(const ChangeSideVm.keys(4).text, '4 top-level keys');
  });

  test('a line of a step-up reads as it always had', () {
    expect(const StepUpDeedVm.set('log_level').text, 'set log_level');
    expect(const StepUpDeedVm.action('update').text, 'update');
    expect(
      const StepUpDeedVm.change(
        op: ChangeOpTag.edit,
        field: 'value',
        to: ChangeSideVm.text('80'),
      ).text,
      'edit value = 80',
    );
    expect(
      [
        for (final a in StepUpAccount.values) StepUpDeedVm.account(a, 'ivan'),
      ].map((d) => d.text),
      [
        'add user ivan',
        'remove user ivan',
        'set roles of ivan',
        'set password of ivan',
        'disable user ivan',
        'enable user ivan',
        'remove device',
      ],
    );
  });

  test('in Ukrainian the words are Ukrainian, the data is not', () async {
    await S.load(const Locale('uk'));
    addTearDown(() => S.load(const Locale('en')));
    expect(const ChangeSideVm.rev(3).text, 'ред. 3');
    expect(const ChangeSideVm.flag(on: true).text, 'увімкнено');
    expect(const ChangeSideVm.text('warn').text, 'warn');
    expect(
      const StepUpDeedVm.account(StepUpAccount.addUser, 'ivan').text,
      'додати користувача ivan',
    );
    expect(const StepUpDeedVm.action('update').text, 'update');
  });

  test('two sides are equal by what they hold', () {
    expect(const ChangeSideVm.rev(3), const ChangeSideVm.rev(3));
    expect(const ChangeSideVm.rev(3), isNot(const ChangeSideVm.rev(4)));
    expect(
      const ChangeSideVm.flag(on: true),
      isNot(const ChangeSideVm.flag(on: false)),
    );
  });
}
