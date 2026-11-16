import 'package:business/wyrm/decode/block_def.dart';
import 'package:business/wyrm/decode/block_library.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/block_info.dart';
import 'package:models/block_type.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// Custom blocks: a definition's `blocks.<name>` (spec 06 0.2.24) and the
/// site's library (`list_blocks`, `get_block`, `put_block`).
void main() {
  final mean = <String, Object?>{
    'description': 'the mean of two',
    'inputs': [
      {
        'name': 'a',
        'to': ['sum.in.0'],
        'default': 1,
      },
      {'name': 'b', 'to': 'sum.in.1', 'description': 'the other'},
    ],
    'outputs': [
      {'name': 'm', 'from': 'half.out'},
    ],
    'nodes': {
      'sum': {'type': 'add'},
      'half': {'type': 'scale', 'k': 0.5},
      'inner1': {'type': 'block:twice'},
    },
    'edges': [
      ['sum.out', 'half.in'],
    ],
    'layout': {
      'sum': [320, 60],
      inputsAtKey: [40, 60],
      libraryMarkKey: [3, 0],
    },
  };

  BlockDef valid(Map<String, Object?> m) => switch (blockDefOf(m)) {
    Valid(:final value) => value,
    final Invalid<BlockDef> i => fail('$i'),
  };

  test('a block definition reads its ports, ends, body and marks', () {
    final d = valid(mean);
    expect(d.description, 'the mean of two');
    expect([for (final p in d.inputs) p.name], ['a', 'b']);
    expect(d.inputs.first.ends, [PortEnd('sum', 'in.0')]);
    expect(d.inputs.first.defaultValue, 1);
    expect(d.inputs.last.ends, [PortEnd('sum', 'in.1')]);
    expect(d.inputs.last.description, 'the other');
    expect(d.outputs.single.ends, [PortEnd('half', 'out')]);
    expect(d.body.blocks.keys.toSet(), {'sum', 'half', 'inner1'});
    expect(d.body.edges.single.target, PortEnd('half', 'in'));
    expect(d.libraryVersion, 3);
    expect(d.inputsAt, (40.0, 60.0));
    expect(d.outputsAt, isNull);
    expect(d.uses, {'twice'});
    expect(d.instances(const CustomType('twice')), 1);
  });

  test('a broken block definition is invalid, with the field', () {
    Invalid<BlockDef> bad(Map<String, Object?> m) => switch (blockDefOf(m)) {
      final Invalid<BlockDef> i => i,
      Valid() => fail('read'),
    };
    expect(
      bad({
        'inputs': [
          {'to': 'a.in'},
        ],
      }).field,
      'inputs[0].name',
    );
    expect(
      bad({
        'inputs': [
          {'name': 'a', 'to': 'nowhere'},
        ],
      }).field,
      'inputs[0].to',
    );
    expect(
      bad({
        'outputs': [
          {'name': 'x', 'from': 7},
        ],
      }).field,
      'outputs[0].from',
    );
    expect(bad({'description': 3}).field, 'description');
    expect(bad({'nodes': 3}).field, 'nodes');
    expect(bad({'layout': 3}).field, 'layout');
  });

  test('the blocks of a definition: a map of maps; others left out', () {
    expect(blockDefsIn(IMap(const {})), isEmpty);
    expect(blockDefsIn(IMap(const {'blocks': 'x'})), isEmpty);
    expect(
      blockDefsIn(
        IMap({
          'blocks': {'mean': mean, 'bad': 1},
        }),
      ).keys,
      ['mean'],
    );
  });

  test('renamed instances, the library mark set and taken off', () {
    final r = withInstancesRenamed(
      mean,
      const CustomType('twice'),
      const CustomType('double'),
    );
    expect(valid(r).uses, {'double'});
    final marked = withLibraryVersion(mean, 9);
    expect(valid(marked).libraryVersion, 9);
    expect(valid(libraryDefOf(marked)).libraryVersion, isNull);
    expect(valid(libraryDefOf(marked)).inputsAt, (40.0, 60.0));
  });

  group('the library', () {
    test('a row of list_blocks', () {
      expect(
        blockInfoOf(
          Value.from({
            'name': 'mean',
            'version': 2,
            'inputs': ['a', 'b'],
            'outputs': ['m'],
          }),
        ),
        Valid(
          BlockInfo(
            name: 'mean',
            version: 2,
            inputs: ['a', 'b'].lock,
            outputs: ['m'].lock,
          ),
        ),
      );
      expect(
        blockInfoOf(Value.from({'version': 2})),
        const Invalid<BlockInfo>('library block', 'name', 'missing'),
      );
      expect(blockInfoOf(const VStr('x')), isA<Invalid<BlockInfo>>());
    });

    test('list_blocks: one array or rows one by one, by name; a row that '
        'does not read is left out', () {
      final rows = [
        Value.from({'name': 'z'}),
        Value.from({'name': 'a'}),
        Value.from({'version': 1}),
      ];
      expect(
        [for (final b in blockListOf(rows, where: 't')) b.name],
        [
          'a',
          'z',
        ],
      );
      expect(
        [
          for (final b in blockListOf([VArray(rows)], where: 't')) b.name,
        ],
        ['a', 'z'],
      );
    });

    test('get_block: the version, the definition and what it requires', () {
      final r = libraryBlockOf(
        Value.from({
          'name': 'mean',
          'version': 4,
          'def': mean,
          'requires': {
            'twice': {'nodes': <String, Object?>{}},
          },
        }),
      );
      expect(
        switch (r) {
          Valid(:final value) => (value.version, value.requires.keys.join()),
          Invalid() => null,
        },
        (4, 'twice'),
      );
      expect(
        libraryBlockOf(Value.from({'def': mean})),
        isA<Invalid<LibraryBlock>>(),
      );
      expect(
        libraryBlockOf(Value.from({'version': 1, 'def': 'x'})),
        const Invalid<LibraryBlock>('library block', 'def', 'not a map'),
      );
      expect(
        libraryBlockOf(
          Value.from({
            'version': 1,
            'def': mean,
            'requires': {'twice': 1},
          }),
        ),
        const Invalid<LibraryBlock>(
          'library block',
          'requires.twice',
          'not a map',
        ),
      );
    });

    test('put_block answers its version', () {
      expect(putBlockVersionOf(Value.from({'version': 5})), const Valid(5));
      expect(putBlockVersionOf(const VNull()), isA<Invalid<int>>());
      expect(nameArgs('mean'), Value.from({'name': 'mean'}));
      expect(putBlockArgs('mean', mean)['def'], Value.from(mean));
    });
  });
}
