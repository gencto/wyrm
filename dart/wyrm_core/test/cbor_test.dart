import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_core/wyrm_core.dart';

String enc(Value v) => hexOf(v.toCbor());

void main() {
  test('shortest floats', () {
    expect(enc(const VFloat(1.0)), 'f93c00');
    expect(enc(const VFloat(120.0)), 'f95780');
    expect(enc(const VFloat(-40.0)), 'f9d100');
    expect(enc(const VFloat(5.960464477539063e-8)), 'f90001'); // f16 subnormal
    expect(enc(const VFloat(100000.0)), 'fa47c35000');
    expect(enc(const VFloat(21.4)), 'fb4035666666666666');
    expect(enc(const VFloat(double.infinity)), 'f97c00');
    expect(enc(const VFloat(double.nan)), 'f97e00');
    expect(enc(const VFloat(-0.0)), 'f98000');
  });

  test('float decode of every width', () {
    for (final h in ['f93c00', 'fa47c35000', 'fb4035666666666666', 'f90001']) {
      final v = Value.fromCbor(hexDecode(h));
      expect(enc(v), h);
    }
  });

  test('integers', () {
    expect(enc(const VInt(0)), '00');
    expect(enc(const VInt(23)), '17');
    expect(enc(const VInt(24)), '1818');
    expect(enc(const VInt(-1)), '20');
    expect(enc(const VInt(-500)), '3901f3');
    expect(enc(const VInt(1760000000123456)), '1b000640b5eecfe240');
    expect(Value.fromCbor(hexDecode('1b000640b5eecfe240')), const VInt(1760000000123456));
  });

  test('canonical text key order uses UTF-8 length', () {
    // "°C" is 2 code units but 3 bytes: it sorts after "abc"? no — same
    // length 3, then bytewise: "abc" (0x61) < "°C" (0xc2).
    final v = VMap({'°C': const VInt(1), 'abc': const VInt(2), 'zz': const VInt(3)});
    expect(enc(v), 'a3627a7a03636162630263c2b04301');
  });

  test('indefinite lengths and tags decode', () {
    // [_ 1, 2] , (_ "a" "b"), tag 1 (1000)
    expect(Value.fromCbor(hexDecode('9f0102ff')), VArray(const [VInt(1), VInt(2)]));
    expect(Value.fromCbor(hexDecode('7f61616162ff')), const VStr('ab'));
    expect(Value.fromCbor(hexDecode('c11903e8')), const VInt(1000));
    expect(Value.fromCbor(hexDecode('bf6161f5ff')), VMap({'a': const VBool(true)}));
  });

  test('Value.from and toDart', () {
    final v = Value.from({'a': 1, 'b': 2.5, 'c': [true, null, 'x'], 'd': Uint8List.fromList([1])});
    expect(Value.fromCbor(v.toCbor()), v);
    expect((v.toDart() as Map)['b'], 2.5);
  });

  test('nesting is bounded (spec rule 6)', () {
    Uint8List nested(int depth, int head) => Uint8List.fromList([...List.filled(depth, head), 0xf6]);
    expect(Value.fromCbor(nested(Value.maxDepth, 0x81)), isA<VArray>());
    for (final head in [0x81, 0xc0]) {
      expect(() => Value.fromCbor(nested(Value.maxDepth + 1, head)), throwsA(isA<CborError>()));
    }
    // far past the limit: refused, not a stack overflow
    expect(() => Value.fromCbor(nested(1000000, 0x81)), throwsA(isA<CborError>()));
  });

  test('truncated input fails', () {
    expect(() => Value.fromCbor(hexDecode('1b0006')), throwsA(isA<CborError>()));
    expect(() => Value.fromCbor(hexDecode('0000')), throwsA(isA<CborError>()));
  });
}
