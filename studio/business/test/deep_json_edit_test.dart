import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/mappers/config_text.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/json_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// JSON nested deeper than [JsonValue.maxDepth] (audit 4 of #135, 1). The
/// checks of a field run in a selector, during a build: typed text, a
/// definition or a pasted block nested without end is refused where it
/// comes in, and nothing past it throws.
void main() {
  /// [depth] lists around a number: `[[1]]` is depth 2. The innermost list
  /// of depth 65 sits past the bound.
  String nested(int depth) => '${'[' * depth}1${']' * depth}';

  group('typed text', () {
    test('a value that fits the bound where it is stored is JSON; one '
        'level more is not', () {
      // a typed value sits up to one level inside a config value
      expect(fieldEditError(nested(63), FieldEdit.json), isNull);
      expect(fieldEditError(nested(64), FieldEdit.json), FieldEditError.json);
      expect(fieldEditError(nested(65), FieldEdit.json), FieldEditError.json);
      // far past any stack: still an answer, not a throw
      expect(
        fieldEditError(nested(200000), FieldEdit.json),
        FieldEditError.json,
      );
    });

    test('a deep text is not saved as a structure: it stays the text', () {
      expect(typedText(nested(63), FieldEdit.json), isA<List<Object?>>());
      expect(typedText(nested(64), FieldEdit.json), nested(64));
      expect(typedText(nested(65), FieldEdit.any), nested(65));
      expect(typedText('{"a": 1}', FieldEdit.any), {'a': 1});
      // JSON null is null (it removes the value), not the text "null"
      expect(typedText('null', FieldEdit.any), isNull);
      expect(typedText('null', FieldEdit.json), isNull);
    });
  });

  test('the text of a value is total over JSON', () {
    expect(jsonEditText(const JsonNull()), '');
    expect(jsonEditText(JsonValue.of('x')), 'x');
    expect(jsonEditText(JsonValue.of(3)), '3');
    expect(jsonEditText(JsonValue.of(true)), 'true');
    expect(jsonEditText(JsonValue.of(const [1])), '[\n  1\n]');
    expect(listRowsIn(const JsonNull()), isEmpty);
    expect(
      listRowsIn(
        JsonValue.of(const [
          {'a': 'x', 'b': 2},
        ]),
      ),
      [
        {'a': 'x', 'b': '2'},
      ],
    );
  });

  group('a definition', () {
    Value deepValue(int depth) {
      Object? v = 1;
      for (var i = 0; i < depth; i++) {
        v = [v];
      }
      return Value.from(v);
    }

    Value def(Value cfgValue) => Value.from({
      'nodes': {
        'n1': {'type': 'constant', 'value': cfgValue},
      },
    });

    test('a config value at the bound reads; one level more is refused', () {
      expect(flowReadOf('f', def(deepValue(64))), isA<Valid<FlowRead>>());
      expect(
        flowReadOf('f', def(deepValue(65))),
        isA<Invalid<FlowRead>>()
            .having((i) => i.field, 'field', 'nodes.n1.value')
            .having((i) => i.reason, 'reason', 'nested too deep'),
      );
    });

    test('a definition nested without end is refused, not walked', () {
      expect(
        flowReadOf('f', def(deepValue(3000))),
        isA<Invalid<FlowRead>>(),
      );
      expect(
        flowReadOf(
          'f',
          Value.from({'nodes': <String, Object?>{}, 'notes': deepValue(65)}),
        ),
        isA<Invalid<FlowRead>>().having((i) => i.field, 'field', 'notes'),
      );
    });

    test('a block port default nested past the bound is refused', () {
      Value withBlock(Value d) => Value.from({
        'nodes': <String, Object?>{},
        'blocks': {
          'b1': {
            'inputs': [
              {'name': 'in', 'to': 'n1.in', 'default': d},
            ],
            'outputs': <Object?>[],
            'nodes': {
              'n1': {'type': 'constant'},
            },
          },
        },
      });
      // the default is shown one level down, in the boundary's `defaults`
      expect(flowReadOf('f', withBlock(deepValue(63))), isA<Valid<FlowRead>>());
      expect(
        flowReadOf('f', withBlock(deepValue(64))),
        isA<Invalid<FlowRead>>(),
      );
    });
  });
}
