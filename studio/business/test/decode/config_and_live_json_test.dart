import 'dart:typed_data';

import 'package:business/wyrm/decode/block_config.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/decode/live_values.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/json_value.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart' show Value;

/// A flow node's config and a sample's value read as JSON, and a flow's
/// `description` (studio-rules §8).
void main() {
  test('a config decodes each field, in its order, once per config', () {
    final cfg = <String, Object?>{
      'key': 'downstream/m/level',
      'k': 2,
      'on': true,
      'none': null,
      'values': {
        'a': [1, 'x'],
      },
    }.lock;
    final c = blockConfigOf(cfg);

    expect(c.keys, ['key', 'k', 'on', 'none', 'values']);
    expect(c['key'], const JsonText('downstream/m/level'));
    expect(c['k'], const JsonNumber(2));
    expect(c['on'], const JsonBool(true));
    expect(c['none'], const JsonNull());
    expect(
      c['values'],
      JsonValue.of(const {
        'a': [1, 'x'],
      }),
    );
    expect(identical(blockConfigOf(cfg), c), isTrue);
    expect(blockConfigOf(const IMapConst({})), isEmpty);
  });

  test('a config that holds no JSON is refused with its type', () {
    expect(
      () => blockConfigOf({'b': Uint8List(2)}.lock),
      throwsArgumentError,
    );
  });

  test("a sample's value as JSON, once per sample; none for bytes", () {
    LiveValue of(Object? v) => LiveValue(
      value: v,
      time: DateTime.utc(2026),
    );

    final map = of({'a': 1});
    expect(liveJsonOf(map), JsonValue.of(const {'a': 1}));
    expect(identical(liveJsonOf(map), liveJsonOf(map)), isTrue);
    expect(liveJsonOf(of(21.5)), const JsonNumber(21.5));
    expect(liveJsonOf(of('on')), const JsonText('on'));
    expect(liveJsonOf(of(null)), const JsonNull());
    expect(liveJsonOf(of(Uint8List(2))), isNull);
    expect(
      liveJsonOf(
        of({
          'a': [Uint8List(1)],
        }),
      ),
      isNull,
    );
  });

  test("a flow's description is a text, or none", () {
    String? description(Object? d) => switch (flowReadOf(
      'tank',
      Value.from({
        'id': 'tank',
        'version': 1,
        'nodes': <String, Object?>{},
        'edges': <Object?>[],
        'description': ?d,
      }),
    )) {
      Valid(:final value) => value.draft.description,
      final Invalid<FlowRead> i => fail('$i'),
    };

    expect(description('tank level'), 'tank level');
    expect(description(null), isNull);
    expect(description(3), isNull, reason: 'not a text: none, never a cast');
    expect(description({'a': 1}), isNull);
  });
}
