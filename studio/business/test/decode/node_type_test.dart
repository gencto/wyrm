import 'dart:async';

import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/node_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/block_type.dart';
import 'package:models/node_type.dart';
import 'package:models/port_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../support/catalog_0221.dart';
import '../support/catalog_0226.dart';
import '../support/catalog_0229.dart';

/// `dataflows` ▸ `node_types` (spec 06): one entry is one [NodeType].
void main() {
  NodeType valid(Map<String, Object?> m) => switch (nodeTypeOf(Value.from(m))) {
    Valid(:final value) => value,
    final Invalid<NodeType> i => fail('$i'),
  };

  final warnings = <String>[];
  StreamSubscription<LogRecord>? sub;
  setUp(() {
    warnings.clear();
    Logger.root.level = Level.ALL;
    sub = decodeLog.onRecord.listen((r) => warnings.add(r.message));
  });
  tearDown(() => sub?.cancel());

  test('every entry of the recorded catalogs decodes, with no warning', () {
    for (final cat in [catalog0221(), catalog0226(), catalog0229()]) {
      for (final m in cat) {
        final t = valid(m);
        expect(t.type.wire, m['type']);
      }
    }
    expect(warnings, isEmpty);
  });

  test('the type is typed once: engine, known by name or not', () {
    expect(valid({'type': 'invoke'}).type.known, KnownBlock.invoke);
    expect(valid({'type': 'sin'}).type, isA<EngineType>());
    expect(valid({'type': 'sin'}).type.known, isNull);
    expect(valid({'type': 'sin'}).type.wire, 'sin');
  });

  test('params: types, editors, the int of older catalogs', () {
    final t = valid({
      'type': 'x',
      'params': [
        {'name': 'a', 'type': 'number'},
        {'name': 'b', 'type': 'int'},
        {'name': 'c'},
        {'name': 'd', 'type': 'bool', 'editor': 'textarea'},
        {'name': 'e', 'type': 'string', 'editor': 'sparkles'},
      ],
    });
    expect(
      [for (final p in t.params) p.type],
      [
        TypeCode.number,
        TypeCode.number,
        TypeCode.string,
        TypeCode.bool_,
        TypeCode.string,
      ],
    );
    expect(t.params[3].editor, ParamEditor.textarea);
    expect(t.params[4].editor, isNull, reason: 'a UI ignores an unknown one');
    expect(warnings, isEmpty);
  });

  test('an unknown param type is dynamic, an unknown port type any, '
      'each with a warning naming the field', () {
    final t = valid({
      'type': 'x',
      'params': [
        {'name': 'a', 'type': 'decimal'},
      ],
      'port_types': {'out': 'tensor', 'in': 'bool'},
    });
    expect(t.params.single.type, TypeCode.dynamic_);
    expect(t.portTypes['out'], PortType.any);
    expect(t.portTypes['in'], PortType.boolean);
    expect(warnings, hasLength(2));
    expect(warnings.first, contains('params[0].type'));
    expect(warnings.last, contains('port_types.out'));
  });

  test('an entry that is no map, or names no type, is invalid', () {
    expect(
      nodeTypeOf(Value.from(['type'])),
      const Invalid<NodeType>('node type', '', 'not a map'),
    );
    expect(
      nodeTypeOf(Value.from({'category': 'Math'})),
      const Invalid<NodeType>('node type', 'type', 'missing'),
    );
    expect(
      nodeTypeOf(Value.from({'type': ''})),
      const Invalid<NodeType>('node type', 'type', 'missing'),
    );
  });
}
