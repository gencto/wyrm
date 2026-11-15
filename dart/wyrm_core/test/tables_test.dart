// Every Dart code table equals its table in spec/tables.json (same codes,
// same names, nothing missing on either side), and the closed sets of
// spec 01 equal the text of the spec.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_core/wyrm_core.dart';

void main() {
  final tables = jsonDecode(
    File('../../spec/tables.json').readAsStringSync(),
  ) as Map<String, Object?>;

  Set<String> spec(String name) {
    final t = tables[name];
    if (t is! Map<String, Object?> || t.isEmpty) {
      fail('table $name missing in tables.json');
    }
    return t.entries.map((e) {
      final k = e.key.startsWith('0x')
          ? int.parse(e.key.substring(2), radix: 16)
          : int.parse(e.key);
      return '$k=${e.value}';
    }).toSet();
  }

  Set<String> dart<T extends WireCode>(List<T> values) =>
      values.map((v) => '${v.code}=${v.wire}').toSet();

  void same<T extends WireCode>(
    String table,
    List<T> values,
    T? Function(int) byCode,
    T? Function(String) byWire,
  ) {
    test(table, () {
      expect(dart(values), spec(table));
      for (final v in values) {
        expect(byCode(v.code), v);
        expect(byWire(v.wire), v);
      }
      expect(byCode(255), isNull);
      expect(byWire('no such name'), isNull);
    });
  }

  same('quality_codes', Quality.values, Quality.fromCode, Quality.fromWire);
  same('perm_levels', Perm.values, Perm.fromCode, Perm.fromWire);
  same('writable_codes', Writable.values, Writable.fromCode, Writable.fromWire);
  same('type_codes', TypeCode.values, TypeCode.fromCode, TypeCode.fromWire);
  same('status_codes', Status.values, Status.fromCode, Status.fromWire);
  same('is_codes', IsCode.values, IsCode.fromCode, IsCode.fromWire);

  test('isCodes map follows IsCode', () {
    expect(
      isCodes.entries.map((e) => '${e.key}=${e.value}').toSet(),
      spec('is_codes'),
    );
  });

  test('aliases', () {
    expect(Perm.write.wireName, 'write');
    expect(Perm.fromName('read'), Perm.read);
    expect(Quality.fromName('bad'), Quality.bad);
  });

  test('a level from a code or a name (spec 06 maxperm)', () {
    expect(Perm.fromValue(const VInt(3)), Perm.write);
    expect(Perm.fromValue(const VStr('write')), Perm.write);
    expect(Perm.fromValue(const VStr('mac')), isNull);
    expect(Perm.fromValue(const VInt(9)), isNull);
    expect(Perm.fromValue(const VBool(true)), isNull);
    expect(Perm.fromValue(null), isNull);
    expect(Perm.config >= Perm.write, isTrue);
    expect(Perm.read < Perm.write, isTrue);
  });

  test('status groups and user codes', () {
    expect(Status.refreshed.group, StatusGroup.progress);
    expect(Status.closed.group, StatusGroup.closed);
    expect(Status.timeout.group, StatusGroup.error);
    expect(const StatusCode(0x41).isUser, isTrue);
    expect(const StatusCode(0x41).isError, isTrue);
  });

  // spec 01, the table of selector parameters:
  // | `agg`, `window` | `~val?history` | `avg|min|…`; …
  test('HistoryAgg equals spec 01', () {
    final text = File('../../spec/01-keyspace.md').readAsStringSync();
    final row = text
        .split('\n')
        .firstWhere((l) => l.startsWith('| `agg`, `window`'), orElse: () => '');
    final m = RegExp(r'\| `([a-z|]+)`; ').firstMatch(row);
    expect(m, isNotNull, reason: 'the agg row of spec 01 moved');
    final names = m!.group(1)!.split('|').toSet();
    expect(names, hasLength(greaterThan(3)));
    expect(HistoryAgg.values.map((a) => a.wire).toSet(), names);
  });

  // spec 01: "- Суфікси `~meta ~val ~set ~act ~state ~def`; …"
  test('DocSuffix names are spec 01 suffixes', () {
    final text = File('../../spec/01-keyspace.md').readAsStringSync();
    final m = RegExp(r'Суфікси `([^`]+)`').firstMatch(text);
    expect(m, isNotNull, reason: 'the suffix line of spec 01 moved');
    final suffixes = m!.group(1)!.split(' ').toSet();
    for (final s in DocSuffix.values) {
      expect(suffixes, contains(s.wire));
      expect(DocSuffix.fromWire(s.wire), s);
    }
  });
}
