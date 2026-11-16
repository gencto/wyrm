import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_check.dart';
import 'package:business/wyrm/decode/flow_clip.dart';
import 'package:business/wyrm/decode/flow_rows.dart';
import 'package:business/wyrm/decode/flow_val.dart';
import 'package:business/wyrm/mappers/block_cfg.dart';
import 'package:business/wyrm/mappers/config_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/port_side.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

/// The answers the flow editor reads besides a definition: `validate`,
/// the rows of `watch` and `preview`, a flow's `~val`, the clipboard, and
/// the config values a block holds.
void main() {
  final now = DateTime.utc(2026, 11, 15);

  group('validate', () {
    test('ok, refused with the engine words, refused with none', () {
      expect(
        flowCheckOf([
          Value.from({'ok': true}),
        ]),
        const Valid(FlowCheck(ok: true)),
      );
      expect(
        flowCheckOf([
          Value.from({'ok': false, 'error': 'a: no such type'}),
        ]),
        const Valid(FlowCheck(ok: false, error: 'a: no such type')),
      );
      expect(
        flowCheckOf([Value.from(<String, Object?>{})]),
        const Valid(FlowCheck(ok: false)),
      );
      expect(
        flowCheckOf([const VStr('bad edge')]),
        const Valid(FlowCheck(ok: false, error: 'bad edge')),
      );
    });

    test('no answer, or an answer of another shape, is invalid', () {
      expect(flowCheckOf(const []), isA<Invalid<FlowCheck>>());
      expect(flowCheckOf(const [VNull()]), isA<Invalid<FlowCheck>>());
      expect(flowCheckOf([const VArray([])]), isA<Invalid<FlowCheck>>());
    });
  });

  group('watch and preview rows', () {
    FlowRow row(Object? r) => switch (flowRowOf(Value.from(r), now: now)) {
      Valid(:final value) => value,
      final Invalid<FlowRow> i => fail('$i'),
    };

    test('a snapshot: in and out samples with quality, params, sinks', () {
      final r = row({
        't': 1763164800000,
        'snapshot': true,
        'nodes': {
          'avg': {
            'in': {
              'in': [20.5, 0],
            },
            'out': {
              'out': [21, 'uncertain'],
              'err': [null, 2],
            },
            'params': {'size_s': 30},
          },
        },
        'sinks': [
          {'node': 'sp', 'value': 7},
          {'value': 1},
        ],
      });
      expect(r.snapshot, isTrue);
      expect(r.t, DateTime.utc(2025, 11, 15));
      expect(r.ports[portKey(PortSide.input, 'avg', 'in')]!.value, 20.5);
      expect(
        r.ports[portKey(PortSide.output, 'avg', 'out')]!.quality,
        m.Quality.uncertain,
      );
      expect(
        r.ports[portKey(PortSide.output, 'avg', 'err')]!.quality,
        m.Quality.bad,
      );
      expect(r.ports[portKey(PortSide.param, 'avg', 'size_s')]!.value, 30);
      expect(r.sinks.keys, ['sp'], reason: 'a sink with no node is left out');
      expect(r.sinks['sp']!.value, 7);
    });

    test('a heartbeat has no t: it is now; a redeploy ends the stream', () {
      expect(row(<String, Object?>{}).t, now);
      final r = row({'redeployed': 5});
      expect((r.redeployed, r.version), (true, 5));
    });

    test('a row of another shape is invalid', () {
      expect(flowRowOf(const VStr('x'), now: now), isA<Invalid<FlowRow>>());
      expect(
        flowRowOf(Value.from({'nodes': <Object?>[]}), now: now),
        const Invalid<FlowRow>('flow row', 'nodes', 'not a map'),
      );
      expect(
        flowRowOf(Value.from({'sinks': <String, Object?>{}}), now: now),
        const Invalid<FlowRow>('flow row', 'sinks', 'not an array'),
      );
    });

    test('an event output: its code and message', () {
      final e = flowEventOf({'event': 'error', 'code': 'busy', 'message': ''});
      expect((e?.code, e?.message), ('busy', null));
      expect(flowEventOf({'value': 1}), isNull);
      expect(flowEventOf(3), isNull);
      expect(watchArgs(4), Value.from({'max_hz': 4}));
    });
  });

  test("a flow's ~val: state, version, who deployed it", () {
    expect(
      flowValOf({
        'state': 0,
        'version': 4.0,
        'deployed_by': 'ann',
        'error': '',
      }),
      const Valid(FlowVal(state: 0, version: 4, deployedBy: 'ann')),
    );
    expect(flowValOf(null), const Valid(FlowVal()));
    expect(flowValOf('x'), isA<Invalid<FlowVal>>());
    final s = flowSummaryOfVal(
      'f',
      const FlowVal(state: 2, error: 'compile'),
    );
    expect((s.problem, s.running, s.draft), ('compile', false, false));
  });

  group('the clipboard', () {
    test('its text reads back as the blocks it holds', () {
      final part = FlowDraft(
        id: '',
        blocks: {
          'a': FlowBlock(id: 'a', type: BlockType.fromWire('not'), x: 20),
        }.lock,
      );
      final text = clipTextFor(part, const {})!;
      final back = switch (clipOf(text)) {
        Valid(:final value) => value,
        final Invalid<FlowDraft> i => fail('$i'),
      };
      expect(back.blocks['a']!.type.wire, 'not');
      expect(back.blocks['a']!.x, 20);
      expect(clipTextFor(const FlowDraft(id: ''), const {}), isNull);
    });

    test('anything else is invalid, with why', () {
      expect(clipOf('{"format": "x"}'), isA<Invalid<FlowDraft>>());
      expect(
        clipOf('{"format": "wyrm-flow-blocks/1", "nodes": {}}'),
        const Invalid<FlowDraft>('flow clipboard', 'nodes', 'missing'),
      );
      expect(
        clipOf(
          '{"format": "wyrm-flow-blocks/1", "nodes": {"a": {"type": "x"}}, '
          '"blocks": 3}',
        ),
        const Invalid<FlowDraft>('flow clipboard', 'blocks', 'not a map'),
      );
    });
  });

  group('the config values the editor reads', () {
    FlowBlock b(Map<String, Object?> cfg) =>
        FlowBlock(id: 'b', type: BlockType.fromWire('invoke'), cfg: cfg.lock);

    test('texts, the scope, args, values, defaults, enabled, names', () {
      final x = b({
        'key': 'downstream/m/a',
        'path': 'downstream/m',
        'action': 'ramp',
        'path_scope': 'downstream/**',
        'args': {'speed': 60},
        'values': {'in.0': 'AHU-'},
        'defaults': {'a': 1},
        'enabled': false,
        'inputs': ['0', '', 1, '1'],
        'node': 7,
      });
      expect(
        (x.cfgKey, x.cfgPath, x.cfgAction),
        (
          'downstream/m/a',
          'downstream/m',
          'ramp',
        ),
      );
      expect(x.cfgNode, isNull, reason: 'a number is no node name');
      expect(x.cfgScope, 'downstream/**');
      expect(rawFields(x.cfgArgs), {'speed': 60});
      expect(x.hasArgs, isTrue);
      expect(rawFields(x.cfgValues), {'in.0': 'AHU-'});
      expect(rawFields(x.cfgDefaults), {'a': 1});
      expect(x.cfgEnabled, isFalse);
      expect(x.namesOf('inputs'), ['0', '1']);
      expect(x.portNamesOf('args'), ['speed']);
      expect(x.namesOf('args'), isNull);
      expect(b(const {}).cfgArgs, isEmpty);
      expect(BlockCfgKey.fromWire('key_scope'), BlockCfgKey.keyScope);
      expect(BlockCfgKey.fromWire('size_s'), isNull);
    });

    test('a value as its editor and its row show it', () {
      expect(jsonEditText(null), '');
      expect(jsonEditText('a'), 'a');
      expect(jsonEditText(2), '2');
      expect(jsonEditText({'a': 1}), '{\n  "a": 1\n}');
      expect(jsonShortText({'a': 1}), '{…}');
      expect(jsonShortText([1]), '[…]');
      expect(jsonShortText(const <Object?>[]), isNull);
      expect(
        listRowsIn([
          {'name': 'a', 'from': 1},
          3,
        ]),
        [
          {'name': 'a', 'from': '1'},
        ],
      );
    });
  });
}
