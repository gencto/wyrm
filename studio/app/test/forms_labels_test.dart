import 'package:app/common/forms.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/param_spec.dart';

/// A form built from an action's parameters reads in words (owner
/// 2026-11-11): the display, else the name in sentence case; snake_case
/// choices in words; the values sent stay the broker's.
void main() {
  test('a parameter without display reads in sentence case', () {
    final f = paramField(const ParamSpec(name: 'a_ab'));
    expect(f.label, 'A ab');
    expect(f.id, 'a_ab');
  });

  test("a parameter's display wins", () {
    final f = paramField(const ParamSpec(name: 'a_ab', display: 'Alpha'));
    expect(f.label, 'Alpha');
  });

  test('choices keep their values and read in words', () {
    final f = paramField(
      const ParamSpec(
        name: 'mode',
        type: 'enum',
        choices: IListConst(['read_back', 'holding', 'f32_wbswap']),
      ),
    );
    expect(f.choices, ['read_back', 'holding', 'f32_wbswap']);
    expect(f.choiceLabels, {'read_back': 'Read back'});
  });
}
