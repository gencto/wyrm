import 'dart:convert';
import 'dart:io';

import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_draft.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A custom block's definition goes back to the engine, the preview and
/// the clipboard as it came (spec 06 0.2.24): its descriptions, a
/// default, no `layout` when it had none, and the fields the editor does
/// not read — on the block and on its inputs and outputs — kept.
void main() {
  Map<String, Object?> fixture(String name) =>
      (jsonDecode(
                File('test/support/flows/$name').readAsStringSync(),
              )!
              as Map)
          .cast<String, Object?>();

  /// A definition written in this test: a block with descriptions, a
  /// default, no `layout`, and an unknown field on an input, on an output
  /// and on the block.
  final spec = <String, Object?>{
    'id': 'spec_blocks',
    'version': 3,
    'blocks': {
      'gain': {
        'description': 'k times in',
        'inputs': [
          {
            'name': 'in',
            'to': 'm.in.0',
            'description': 'the value',
            'x_input_future': {'a': 1},
          },
          {'name': 'k', 'to': 'm.in.1', 'default': 2},
        ],
        'outputs': [
          {
            'name': 'out',
            'from': 'm.out',
            'description': 'in × k',
            'x_output_future': [1, 2],
          },
        ],
        'nodes': {
          'm': {'type': 'multiply'},
        },
        'edges': <Object?>[],
        'x_block_future': 'kept',
      },
    },
    'nodes': {
      'p': {'type': 'subscribe', 'key': 'downstream/mock/p0'},
      'g': {'type': 'block:gain'},
    },
    'edges': [
      ['p.out', 'g.in'],
    ],
    'layout': {
      'p': [20, 20],
      'g': [300, 20],
    },
  };

  FlowDraft read(Map<String, Object?> def) =>
      switch (flowReadOf(def['id']! as String, Value.from(def))) {
        Valid(:final value) => value.draft,
        Invalid(:final field, :final reason) => fail('$field: $reason'),
      };

  Object? json(Value v) => jsonDecode(jsonEncode(toDart(v)));

  for (final (name, def) in [
    ('a spec-shaped block', spec),
    ("the auditor's two blocks", fixture('custom_blocks.json')),
    ('with unknown fields', fixture('custom_blocks_unknown.json')),
  ]) {
    group(name, () {
      final blocks = def['blocks'];

      test('deploy sends the definition as it came', () {
        final d = read(def);
        expect(json(defOf(d, def['version']! as int)), def);
      });

      test('the preview runs the same blocks', () {
        final sent = json(previewDefOf(read(def)))! as Map<String, Object?>;
        expect(sent['blocks'], blocks);
      });

      test('the clipboard carries the same blocks', () {
        final d = read(def);
        final text = clipTextOf(d, d.blocks.keys.toSet())!;
        final clip = jsonDecode(text) as Map<String, Object?>;
        expect(clip['blocks'], blocks);
      });
    });
  }

  test('a block with no layout is written without one', () {
    final sent =
        json(defOf(read(fixture('custom_blocks.json')), 7))!
            as Map<String, Object?>;
    final other = (sent['blocks']! as Map)['other']! as Map;
    expect(other.containsKey('layout'), isFalse);
  });
}
