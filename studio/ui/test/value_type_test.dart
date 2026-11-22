import 'package:flutter_test/flutter_test.dart';
import 'package:ui/indicators/value_type.dart';

/// Board *Icons* "Point: add its type tag": what a point carries beside
/// its name, by the type of its value.
void main() {
  test('a point carries its type tag', () {
    expect(
      [
        for (final t in [
          ValueType.numeric,
          ValueType.bool_,
          ValueType.enum_,
          ValueType.string,
          ValueType.map,
        ])
          t.tag,
      ],
      ['.0', '01', '≡', 'Aa', '{}'],
    );
  });

  test('every type has a tag, and a structure of any kind the same one', () {
    expect(ValueType.array.tag, ValueType.map.tag);
    expect(ValueType.dynamic_.tag, ValueType.map.tag);
    expect(ValueType.binary.tag, '0x');
    expect(ValueType.null_.tag, '·');
  });
}
