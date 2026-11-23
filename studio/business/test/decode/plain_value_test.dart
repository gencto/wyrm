import 'dart:typed_data';

import 'package:business/wyrm/decode/live_value.dart';
import 'package:business/wyrm/decode/plain_value.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/plain_entry.dart';
import 'package:models/plain_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A sample's value as the viewers read it (studio-rules §8): decoded
/// once into a [PlainValue], from the form a sample holds.
void main() {
  PlainValue sample(Value v) =>
      plainValueOf(liveValueOf(Sample(v, t: 1)).value);

  test('every form a sample of the wire takes', () {
    expect(sample(const VNull()), const PlainValue.nothing());
    expect(sample(const VBool(true)), const PlainValue.flag(true));
    expect(sample(const VInt(7)), const PlainValue.number(7));
    expect(sample(const VFloat(2.5)), const PlainValue.number(2.5));
    expect(sample(const VStr('x')), const PlainValue.text('x'));
    final b = sample(VBytes(Uint8List.fromList([1, 2])));
    expect(b, isA<PlainValueBytes>());
    expect((b as PlainValueBytes).bytes, [1, 2]);
    final l = sample(Value.from([1, 'a']));
    expect(l, isA<PlainValueList>());
    expect((l as PlainValueList).items, [
      const PlainValue.number(1),
      const PlainValue.text('a'),
    ]);
    final m = sample(Value.from({'k': 1}));
    expect((m as PlainValueMap).entries, [
      const PlainEntry(key: 'k', textKey: true, value: PlainValue.number(1)),
    ]);
  });

  test('a list of numbers stays a list; bytes only as bytes', () {
    expect(plainValueOf([1, 2, 3]), isA<PlainValueList>());
    expect(plainValueOf(Uint8List.fromList([1])), isA<PlainValueBytes>());
  });

  test('a key that is no text is marked, in its order', () {
    final m = plainValueOf({1: 'a', 'b': 2}) as PlainValueMap;
    expect([for (final e in m.entries) e.key], ['1', 'b']);
    expect([for (final e in m.entries) e.textKey], [false, true]);
  });

  test('a map or a list is read once; anything else is its text', () {
    final raw = {'a': 1};
    expect(identical(plainValueOf(raw), plainValueOf(raw)), isTrue);
    expect(plainValueOf(raw).raw, same(raw));
    final o = plainValueOf(DateTime.utc(2026)) as PlainValueOther;
    expect(o.type, 'DateTime');
    expect(o.text, '${DateTime.utc(2026)}');
  });

  test('a JSON text, typed; none for a text that is no JSON', () {
    expect(plainJsonOf('[1]'), isA<PlainValueList>());
    expect(plainJsonOf('3'), const PlainValue.number(3));
    expect(plainJsonOf('{oops'), isNull);
  });
}
