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
}
