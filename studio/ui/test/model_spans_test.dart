import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/conversation.dart';

void main() {
  const code = TextStyle(fontFamily: 'mono');
  List<(String, bool, bool)> read(String text) => [
    for (final s in modelSpans(text, code: code).cast<TextSpan>())
      (s.text!, s.style?.fontWeight == FontWeight.w600, s.style == code),
  ];

  test('strong and code lose their marks', () {
    expect(read('It is **22,0 °C** at ` wy/plant/d1/temp ` now.'), [
      ('It is ', false, false),
      ('22,0 °C', true, false),
      (' at ', false, false),
      ('wy/plant/d1/temp', false, true),
      (' now.', false, false),
    ]);
  });

  test('a mark with no partner stays as text', () {
    expect(read('2 ** 3 and a ` tick'), [
      ('2 ** 3 and a ` tick', false, false),
    ]);
    expect(read('**** and ``'), [('**** and ``', false, false)]);
    expect(read('**a\nb**'), [('**a\nb**', false, false)]);
  });

  test('plain text is one span', () {
    expect(read('Nothing to mark.'), [('Nothing to mark.', false, false)]);
    expect(modelSpans('', code: code), isEmpty);
  });
}
