// WireMap: required, optional and closed-set reads, and the paths of their
// errors.

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_core/wyrm_core.dart';

Matcher decodeError(String path, {String? got}) => isA<DecodeError>()
    .having((e) => e.path, 'path', path)
    .having((e) => e.got, 'got', got ?? anything);

void main() {
  final m = WireMap.of(
    VMap({
      's': const VStr('x'),
      'e': const VStr(''),
      'i': const VInt(7),
      'f': const VFloat(1.5),
      'b': const VBool(true),
      'y': VBytes(Uint8List.fromList([1, 2])),
      'n': const VNull(),
      'ss': VArray([const VStr('a'), const VStr('b')]),
      'bad': VArray([const VStr('a'), const VInt(1)]),
      'p': const VStr('write'),
      'pc': const VInt(2),
      'q': const VStr('mac'),
      'm': VMap({'k': const VInt(1)}),
      'l': VArray([
        VMap({'k': const VInt(1)}),
        VMap({'k': const VStr('two')}),
      ]),
    }),
    'T',
  );

  test('not a map', () {
    expect(
      () => WireMap.of(const VStr('x'), 'T'),
      throwsA(decodeError('T', got: 'text')),
    );
    expect(
      () => WireMap.of(null, 'T'),
      throwsA(decodeError('T', got: 'absent')),
    );
  });

  test('required fields', () {
    expect(m.str('s'), 'x');
    expect(m.integer('i'), 7);
    expect(m.number('i'), 7.0);
    expect(m.number('f'), 1.5);
    expect(m.boolean('b'), isTrue);
    expect(m.bytes('y'), [1, 2]);
    expect(m.strings('ss'), ['a', 'b']);
    expect(() => m.str('i'), throwsA(decodeError('T.i', got: 'an integer')));
    expect(() => m.str('none'), throwsA(decodeError('T.none', got: 'absent')));
    expect(() => m.integer('f'), throwsA(decodeError('T.f', got: 'a float')));
    expect(() => m.strings('bad'), throwsA(decodeError('T.bad[1]')));
  });

  test('optional fields: absent or null is null, another type is an error', () {
    expect(m.strOrNull('none'), isNull);
    expect(m.strOrNull('n'), isNull);
    expect(m.strOr('none', 'd'), 'd');
    expect(m.textOrNull('e'), isNull);
    expect(m.integerOr('none', 3), 3);
    expect(m.booleanOr('none', false), isFalse);
    expect(m.stringsOr('none'), isEmpty);
    expect(m.has('n'), isFalse);
    expect(m.has('s'), isTrue);
    expect(() => m.strOrNull('i'), throwsA(decodeError('T.i')));
    expect(() => m.integerOrNull('s'), throwsA(decodeError('T.s')));
    expect(() => m.booleanOrNull('s'), throwsA(decodeError('T.s')));
  });

  test('closed sets name the unknown member', () {
    expect(m.perm('p'), Perm.write);
    expect(m.perm('pc'), Perm.read);
    expect(m.permOrNull('none'), isNull);
    expect(() => m.perm('q'), throwsA(decodeError('T.q', got: "'mac'")));
    expect(
      () => m.name('q', HistoryAgg.values),
      throwsA(decodeError('T.q', got: "'mac'")),
    );
    expect(m.nameOr('none', HistoryAgg.values, HistoryAgg.avg), HistoryAgg.avg);
    final e = (() {
      try {
        m.name('q', DocSuffix.values);
      } on DecodeError catch (e) {
        return e;
      }
      return null;
    })();
    expect(e?.expected, 'one of ~state, ~def');
    expect(
      e.toString(),
      contains("T.q: expected one of ~state, ~def, got 'mac'"),
    );
  });

  test('nested maps and lists carry their path', () {
    expect(m.map('m').integer('k'), 1);
    expect(m.mapOrNull('none'), isNull);
    expect(() => m.map('s'), throwsA(decodeError('T.s')));
    expect(
      () => m.list('l', (v, p) => WireMap.of(v, p).integer('k')),
      throwsA(decodeError('T.l[1].k', got: 'text')),
    );
    expect(m.listOr('none', (v, p) => 0), isEmpty);
  });
}
