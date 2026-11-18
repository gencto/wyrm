import 'package:models/json_value.dart';
import 'package:test/test.dart';

/// A config value of a flow definition, decoded once.
void main() {
  test('every JSON shape has its case, and gives back what it decoded', () {
    expect(JsonValue.of(null), isA<JsonNull>());
    expect(JsonValue.of(true), isA<JsonBool>());
    expect((JsonValue.of(2.5) as JsonNumber).value, 2.5);
    expect((JsonValue.of('a') as JsonText).text, 'a');
    final m = <String, Object?>{
      'k': [1, 'x', ''],
      'n': null,
    };
    final v = JsonValue.of(m);
    expect(v, isA<JsonMap>());
    expect(v.raw, same(m));
    expect((v as JsonMap).entries, m);
    expect((v.fields['k']! as JsonList).names, ['x']);
  });

  test('a map or a list decodes once per object', () {
    final m = <String, Object?>{'a': 1};
    expect(identical(JsonValue.of(m), JsonValue.of(m)), isTrue);
    expect(identical(JsonValue.of(m), JsonValue.of({...m})), isFalse);
  });

  test('a value that is not JSON says so', () {
    expect(() => JsonValue.of(DateTime(2026)), throwsArgumentError);
  });

  test('two values are equal when they hold the same JSON', () {
    JsonValue of(Object? v) => JsonValue.of(v);
    expect(of('a'), of('a'));
    expect(of('a'), isNot(of('b')));
    expect(of(1), of(1.0));
    expect(of(true), isNot(of(1)));
    expect(of(null), of(null));
    expect(of('1'), isNot(of(1)));
    // two decodes of equal structures, not the same object
    expect(
      of({
        'a': [1, 'x', null],
        'b': {'c': true},
      }),
      of({
        'a': [1, 'x', null],
        'b': {'c': true},
      }),
    );
    expect(of([1, 2]), isNot(of([2, 1])));
    expect(of({'a': 1}), isNot(of({'a': 2})));
    expect(of('a').hashCode, of('a').hashCode);
    expect(of([1, 2]).hashCode, of([1, 2]).hashCode);
  });

  test('a value nested deeper than the bound is refused, not walked', () {
    Object? nest(int depth) {
      Object? v = 1;
      for (var i = 0; i < depth; i++) {
        v = [v];
      }
      return v;
    }

    expect(JsonValue.of(nest(JsonValue.maxDepth)), isA<JsonList>());
    expect(
      () => JsonValue.of(nest(JsonValue.maxDepth + 1)),
      throwsA(isA<JsonTooDeep>()),
    );
    // far past any stack: refused at the bound
    expect(() => JsonValue.of(nest(200000)), throwsA(isA<JsonTooDeep>()));
    expect(JsonValue.isJson(nest(200000)), isFalse);
    expect(JsonValue.tryOf(nest(200000)), isNull);
    Object? maps = 1;
    for (var i = 0; i < 100; i++) {
      maps = {'a': maps};
    }
    expect(() => JsonValue.of(maps), throwsA(isA<JsonTooDeep>()));
  });
}
