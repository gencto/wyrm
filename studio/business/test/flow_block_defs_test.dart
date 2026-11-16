import 'dart:convert';
import 'dart:io';

import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/engine_port.dart';
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
    // Nested unknown fields, a `null` default, fractional inner places
    // (of nodes and of the boundary blocks), a block with no layout.
    ('kept as they came', fixture('custom_blocks_kept.json')),
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

  group("the auditor's custom4", () {
    // A flow with no `layout` of its own: the editor writes every block's
    // place there (as before the rewrite); its custom blocks are kept.
    final def = fixture('custom_blocks_mine.json');
    final blocks = def['blocks'];
    test('deploy keeps its blocks, a null default and 5.4/7.6 too', () {
      final sent = json(defOf(read(def), 2))! as Map<String, Object?>;
      expect(sent['blocks'], blocks);
      expect({...sent}..remove('layout'), def);
    });
    test('preview and clipboard keep its blocks', () {
      final d = read(def);
      expect(
        (json(previewDefOf(d))! as Map<String, Object?>)['blocks'],
        blocks,
      );
      final clip = jsonDecode(clipTextOf(d, d.blocks.keys.toSet())!) as Map;
      expect(clip['blocks'], blocks);
    });
  });

  group('opened and left again (enter, leave)', () {
    test('with no edit, the flow is the definition it was', () {
      for (final name in [
        'custom_blocks_kept.json',
        'custom_blocks_mine.json',
        'custom_blocks.json',
        'custom_blocks_unknown.json',
      ]) {
        final def = fixture(name);
        final d = read(def);
        for (final block in d.defs.keys) {
          final left = foldInside(d, block, insideDraftOf(d, block)!);
          expect(
            json(defOf(left, 1)),
            json(defOf(d, 1)),
            reason: '$name: $block',
          );
        }
      }
    });

    test('an edit inside is in the definition; the rest is kept', () {
      final def = fixture('custom_blocks_kept.json');
      final d = read(def);
      final inner = insideDraftOf(d, 'window')!;
      final w = inner.blocks['w']!;
      final edited = inner.copyWith(
        blocks: inner.blocks.add(
          'w',
          w.copyWith(cfg: w.cfg.add('fn', 'max'), x: 100, y: 200),
        ),
      );
      final sent =
          json(defOf(foldInside(d, 'window', edited), 5))!
              as Map<String, Object?>;
      final blocks = sent['blocks']! as Map<String, Object?>;
      final window = blocks['window']! as Map<String, Object?>;
      final was =
          (def['blocks']! as Map<String, Object?>)['window']!
              as Map<String, Object?>;
      // The edit: the node's config and its new place.
      final nodes = window['nodes']! as Map<String, Object?>;
      expect((nodes['w']! as Map)['fn'], 'max');
      final layout = window['layout']! as Map<String, Object?>;
      expect(layout['w'], [100, 200]);
      // The rest as it came: the other places, the ports with their
      // unknown fields and null default, the block's own unknown field.
      expect(layout['t'], [300, 40]);
      expect(layout['_~port~in'], [0.5, 10]);
      expect(window['inputs'], was['inputs']);
      expect(window['outputs'], was['outputs']);
      expect(window['x_block'], was['x_block']);
      expect(window['description'], was['description']);
      expect(blocks['bare'], (def['blocks']! as Map)['bare']);
    });
  });

  test('a moved inner node is written on whole numbers', () {
    final d = read(fixture('custom_blocks_kept.json'));
    final def = d.defs['window']!;
    final w = def.body.blocks['w']!;
    final moved = def.copyWith(
      body: def.body.copyWith(
        blocks: def.body.blocks.add('w', w.copyWith(x: 13.7, y: 40.5)),
      ),
    );
    final sent =
        json(defOf(d.copyWith(defs: d.defs.add('window', moved)), 5))!
            as Map<String, Object?>;
    final blocks = sent['blocks']! as Map<String, Object?>;
    final window = blocks['window']! as Map<String, Object?>;
    final layout = window['layout']! as Map<String, Object?>;
    expect(layout['w'], [14, 41]);
    expect(layout['t'], [300, 40]);
    expect(layout['_~port~in'], [0.5, 10]);
  });

  test('a block with no layout is written without one', () {
    final sent =
        json(defOf(read(fixture('custom_blocks.json')), 7))!
            as Map<String, Object?>;
    final other = (sent['blocks']! as Map)['other']! as Map;
    expect(other.containsKey('layout'), isFalse);
  });

  test('a port named as an engine port is one, as in a catalog type', () {
    final d = read({
      'id': 'ports',
      'blocks': {
        'pass': {
          'inputs': [
            {'name': 'in', 'to': 'h.in'},
            {'name': 'trigger', 'to': 'h.in'},
            {'name': 'level', 'to': 'h.in'},
          ],
          'outputs': [
            {'name': 'out', 'from': 'h.out'},
            {'name': 'error', 'from': 'h.out'},
            {'name': 'mean', 'from': 'h.out'},
          ],
          'nodes': {
            'h': {'type': 'hub'},
          },
          'edges': <Object?>[],
        },
      },
      'nodes': <String, Object?>{},
    });
    final t = customTypeOf('pass', d.defs['pass']!);
    expect(t.knownInputs.unlock, {
      'in': EnginePort.in_,
      'trigger': EnginePort.trigger,
    });
    expect(t.knownOutputs.unlock, {
      'out': EnginePort.out,
      'error': EnginePort.error,
    });
  });
}
