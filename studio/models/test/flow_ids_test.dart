import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/port_end.dart';
import 'package:models/port_type.dart';
import 'package:test/test.dart';

/// The two parses the flow editor keys on: a block's type by its wire
/// name, a field by its key.
void main() {
  test('a known engine type is one value, however it is made', () {
    for (final k in KnownBlock.values) {
      final t = BlockType.fromWire(k.wire);
      expect(t, EngineType.known(k));
      expect(t.hashCode, EngineType.known(k).hashCode);
      expect(t.known, k);
      expect(t.wire, k.wire);
    }
  });

  test('engine, custom and boundary types round-trip their wire name', () {
    for (final w in ['sin', 'block:mean', 'block~inputs', 'block~outputs']) {
      expect(BlockType.fromWire(w).wire, w);
    }
    expect(BlockType.fromWire('sin'), isA<EngineType>());
    expect(BlockType.fromWire('sin').known, isNull);
    expect(BlockType.fromWire('block:mean'), const CustomType('mean'));
    expect(BlockType.fromWire('block~inputs'), BoundaryType.inputs);
    expect(BlockType.fromWire('block~outputs'), BoundaryType.outputs);
    expect(
      {BlockType.fromWire('scale'), KnownBlock.scale.type},
      hasLength(1),
      reason: 'a map keyed by type finds it either way',
    );
  });

  test('a field round-trips its key; the form row is no field', () {
    const fields = [
      FieldId.param('k'),
      FieldId.input('in.0'),
      FieldId.output('out'),
      FieldId.arg('speed'),
    ];
    for (final f in fields) {
      expect(FieldId.fromKey(f.key), f);
      expect(RowId.fromKey(f.key), f);
    }
    expect(const FieldId.param('k').key, 'p:k');
    expect(const FieldId.input('in.0').key, 'in:in.0');
    expect(RowId.fromKey('form'), isA<FormRow>());
    expect(FieldId.fromKey('form'), isNull);
    expect(FieldId.fromKey('zz:a'), isNull);
    expect(FieldId.fromKey('p:'), isNull);
    expect(
      const FieldAt('pct', FieldId.param('k')).toString(),
      'pct/p:k',
    );
  });

  test('a port end and a port type', () {
    expect(const PortEnd('a', 'in.0').wire, 'a.in.0');
    expect(PortType.fromWire('bool'), PortType.boolean);
    expect(PortType.fromWire('tensor'), isNull);
    expect(PortType.number.fits(PortType.any), isTrue);
    expect(PortType.number.fits(PortType.boolean), isFalse);
  });
}
