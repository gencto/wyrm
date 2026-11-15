import 'dart:convert';
import 'dart:io';

import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/decode/flow_permissions.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_permissions.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../support/block_types.dart';

/// Spec 06 0.2.32: `permissions.maxperm` is a code (`0 none … 3 write`) or
/// a name. The flow editor cast it to a string, and a flow deployed with a
/// code (a tool, the agent) broke the editor's view-model ("type 'int' is
/// not a subtype of type 'String?'", 2026-11-15).
void main() {
  Value perms(Object? maxperm) => Value.from({'maxperm': maxperm});

  test('every level of spec/tables.json reads the same by code and name', () {
    final levels =
        (jsonDecode(File('../../spec/tables.json').readAsStringSync())
                as Map<String, Object?>)['perm_levels']!
            as Map<String, Object?>;
    expect(levels, isNotEmpty);
    for (final MapEntry(:key, :value) in levels.entries) {
      final byCode = switch (flowPermissionsOf(perms(int.parse(key)))) {
        Valid(:final value) => value,
        Invalid() => null,
      };
      final byName = switch (flowPermissionsOf(perms(value))) {
        Valid(:final value) => value,
        Invalid() => null,
      };
      expect(byCode?.maxperm?.wireName, value, reason: 'code $key');
      expect(byName, byCode, reason: 'name $value');
    }
  });

  test('no permissions, or no maxperm, is valid and names none', () {
    expect(flowPermissionsOf(null), const Valid(FlowPermissions()));
    expect(
      flowPermissionsOf(Value.from(<String, Object?>{'token': 't'})),
      const Valid(FlowPermissions()),
    );
  });

  test('anything else is invalid with the field, not a fault', () {
    for (final bad in [
      99,
      'admin',
      const ['write'],
    ]) {
      expect(
        flowPermissionsOf(perms(bad)),
        const Invalid<FlowPermissions>(
          'flow permissions',
          'maxperm',
          'not a level',
        ),
        reason: '$bad',
      );
    }
    expect(
      flowPermissionsOf(Value.from('write')),
      const Invalid<FlowPermissions>('flow permissions', '', 'not a map'),
    );
  });

  test('a draft with a bad maxperm has none, and the log names the field', () {
    final logged = <String>[];
    final sub = decodeLog.onRecord.listen((r) => logged.add(r.message));
    addTearDown(sub.cancel);
    final d = flowDraftOf(
      'f',
      Value.from({
        'id': 'f',
        'permissions': {'maxperm': 'admin'},
        'nodes': <String, Object?>{},
        'edges': <Object?>[],
      }),
    );
    expect(d.permissions, isNull);
    expect(logged, ['flow f: flow permissions.maxperm: not a level']);
  });

  test('a draft carries them typed, and writes them back as they came', () {
    final def = Value.from({
      'id': 'f',
      'permissions': {'maxperm': 3, 'token': 't'},
      'nodes': <String, Object?>{},
      'edges': <Object?>[],
    });
    final d = flowDraftOf('f', def);
    expect(d.permissions?.maxperm, Perm.write);
    expect(
      (toDart(defOf(d, 1))! as Map)['permissions'],
      {'maxperm': 3, 'token': 't'},
    );
  });
}
