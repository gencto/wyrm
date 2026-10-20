// Every Dart code table equals its table in spec/tables.json.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_core/wyrm_core.dart';

void main() {
  final tables = jsonDecode(File('../../spec/tables.json').readAsStringSync()) as Map<String, Object?>;

  Set<String> spec(String name) => (tables[name] as Map<String, Object?>).entries.map((e) {
        final k = e.key.startsWith('0x') ? int.parse(e.key.substring(2), radix: 16) : int.parse(e.key);
        return '$k=${e.value}';
      }).toSet();

  Set<String> dart<T>(List<T> values, int Function(T) code, String Function(T) name) =>
      values.map((v) => '${code(v)}=${name(v)}').toSet();

  test('quality_codes', () => expect(dart(Quality.values, (v) => v.code, (v) => v.wireName), spec('quality_codes')));
  test('perm_levels', () => expect(dart(Perm.values, (v) => v.code, (v) => v.wireName), spec('perm_levels')));
  test('writable_codes', () => expect(dart(Writable.values, (v) => v.code, (v) => v.wireName), spec('writable_codes')));
  test('type_codes', () => expect(dart(TypeCode.values, (v) => v.code, (v) => v.wireName), spec('type_codes')));
  test('status_codes', () => expect(dart(Status.values, (v) => v.code, (v) => v.wireName), spec('status_codes')));
  test('is_codes', () => expect(isCodes.entries.map((e) => '${e.key}=${e.value}').toSet(), spec('is_codes')));

  test('status groups and user codes', () {
    expect(Status.refreshed.group, StatusGroup.progress);
    expect(Status.closed.group, StatusGroup.closed);
    expect(Status.timeout.group, StatusGroup.error);
    expect(const StatusCode(0x41).isUser, isTrue);
    expect(const StatusCode(0x41).isError, isTrue);
  });
}
