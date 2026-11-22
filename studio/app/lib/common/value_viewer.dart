import 'dart:convert';
import 'dart:typed_data';

import 'package:business/wyrm/decode/plain_value.dart';
import 'package:business/wyrm/decode/table_value.dart';
import 'package:business/wyrm/mappers/csv_table.dart';
import 'package:business/wyrm/mappers/table_value.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:models/plain_entry.dart';
import 'package:models/plain_value.dart';
import 'package:models/quality.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/tables/table_edits.dart';
import 'package:ui/trees/json_tree.dart';

/// Bytes a viewer dumps as hex; the rest is counted (16 a row).
const int _maxBytes = 16 * 1024;

/// The viewer of a value (a flow field's, a point's): [value] as a live
/// value holds it, drawn by its type (docs/studio.md §6.8).
///
/// - a table (ADR 0044 §2: `{columns, rows}`, or with [rowsOfMaps] a list
///   of maps): a grid of all its rows ([tableDataOf]);
/// - a date of the flow engine ([date]: µs since the epoch): the local date
///   and time, the instant in UTC and the number beside it;
/// - a map or a list, or a text that is a JSON map or list: a tree;
/// - a text: numbered lines;
/// - a number with its [unit] (an enum by its name in [choices]);
/// - a bool: a mark and its word;
/// - `Uint8List` alone is binary (a JSON list of ints stays a list): hex;
/// - nothing known ([known] false): `no value`.
///
/// `copy` of the result is the raw value as JSON, a text as itself. A table
/// with no columns is `a table with no columns`, unless it is [editable]
/// (its grid adds the first one).
ValueViewerVm valueViewerOf({
  required String title,
  required Object? value,
  bool known = true,
  String? unit,
  List<String> choices = const [],
  QualityMarkVm? quality,
  bool rowsOfMaps = false,
  bool date = false,
  bool editable = false,
}) {
  final s = S.current;
  final t = known ? tableDataOf(value, rowsOfMaps: rowsOfMaps) : null;
  if (t != null) {
    return ValueViewerVm(
      title: title,
      type: 'table',
      size: [
        s.sizeRows(t.rows.length),
        s.sizeColumns(t.columns.length),
      ].join(' · '),
      content: t.columns.isEmpty && !editable
          ? EmptyContentVm(s.tableNoColumns)
          : TableContentVm(t),
      copy: _prettyOnce(value!),
      quality: quality,
    );
  }
  if (known && date && dateText(value) != null) {
    return ValueViewerVm(
      title: title,
      type: 'date',
      content: NumberContentVm(
        dateText(value)!,
        unit: '${dateTextUtc(value)} · ${valueText(value)} µs',
      ),
      copy: jsonEncode(value),
      quality: quality,
    );
  }
  if (!known) {
    return ValueViewerVm(
      title: title,
      type: '—',
      content: EmptyContentVm(s.noValue),
      copy: '',
      quality: quality,
    );
  }
  final shown = plainValueOf(value);
  switch (shown) {
    case PlainValueNothing():
      return ValueViewerVm(
        title: title,
        type: 'null',
        content: const EmptyContentVm('null'),
        copy: 'null',
        quality: quality,
      );
    case PlainValueBytes(bytes: final b):
      return ValueViewerVm(
        title: title,
        type: 'bytes',
        size: s.sizeBytes(b.length),
        content: BytesContentVm(hexRows(b)),
        copy: [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join(),
        quality: quality,
      );
    case PlainValueMap(:final entries):
      return ValueViewerVm(
        title: title,
        type: 'map',
        size: s.sizeKeys(entries.length),
        content: JsonContentVm(jsonNode(shown)),
        copy: _pretty(shown),
        quality: quality,
      );
    case PlainValueList(:final items):
      return ValueViewerVm(
        title: title,
        type: 'list',
        size: s.sizeItems(items.length),
        content: JsonContentVm(jsonNode(shown)),
        copy: _pretty(shown),
        quality: quality,
      );
    case PlainValueText(text: final t):
      final lines = t.split('\n');
      final json = _json(t);
      return ValueViewerVm(
        title: title,
        type: json == null ? 'string' : 'string · JSON',
        size: [
          s.sizeChars(t.length),
          if (lines.length > 1) s.sizeLines(lines.length),
        ].join(' · '),
        content: json == null
            ? TextContentVm(lines)
            : JsonContentVm(jsonNode(json)),
        copy: t,
        quality: quality,
      );
    case PlainValueFlag(value: final b):
      return ValueViewerVm(
        title: title,
        type: 'bool',
        content: FlagContentVm(
          value: b,
          word: choices.length == 2 ? choices[b ? 1 : 0] : '$b',
        ),
        copy: '$b',
        quality: quality,
      );
    case PlainValueNumber(value: final n):
      final named = valueText(n, choices: choices);
      final isEnum = choices.isNotEmpty && named != valueText(n);
      return ValueViewerVm(
        title: title,
        type: isEnum ? 'enum' : 'number',
        content: NumberContentVm(
          named,
          unit: isEnum ? '= ${valueText(n)}' : (unit ?? ''),
        ),
        copy: jsonEncode(n),
        quality: quality,
      );
    case PlainValueOther(text: final t, :final type):
      return ValueViewerVm(
        title: title,
        type: type,
        size: s.sizeChars(t.length),
        content: TextContentVm(t.split('\n')),
        copy: t,
        quality: quality,
      );
  }
}

/// The grids of the tables already read: one [TableDataVm] (and one JSON
/// text) per value, so a view-model built again for the same value holds
/// the same instance and compares equal at once (a table may hold 10 000
/// rows, and `fromStore` runs on every dispatch).
final _tables = Expando<TableDataVm>('tables');
final _jsonTexts = Expando<String>('json texts');

/// [v] as the grid of a table ([tableValueOf]), the same instance for the
/// same value; null when it is none.
TableDataVm? tableDataOf(Object? v, {bool rowsOfMaps = false}) =>
    switch (tableValueOf(v, rowsOfMaps: rowsOfMaps)) {
      final t? => _tables[t] ??= TableDataVm(t.columns, [
        for (final r in t.rows) [for (final c in r) cellVmOf(c)],
      ]),
      null => null,
    };

/// [_pretty] of the table [v], once per value.
String _prettyOnce(Object v) => _jsonTexts[v] ??= _pretty(plainValueOf(v));

/// A cell of a table as the grid holds it.
CellVm cellVmOf(PlainValue v) => switch (v) {
  PlainValueNothing() => const NullCell(),
  PlainValueFlag(:final value) => FlagCell(value),
  PlainValueNumber(:final value) => NumberCell(value),
  PlainValueText(:final text) => TextCell(text),
  PlainValueBytes(:final bytes) => BytesCell(bytes),
  PlainValueList(:final items, :final raw) => ListCell([
    for (final x in items) cellVmOf(x),
  ], raw: raw),
  PlainValueMap(:final entries, :final raw) => MapCell([
    for (final e in entries) CellEntryVm(e.key, cellVmOf(e.value)),
  ], raw: raw),
  PlainValueOther(:final text, :final raw) => OtherCell(text, raw: raw),
};

/// A cell of the grid as the CSV writer reads it.
PlainValue _plainOf(CellVm c) => switch (c) {
  NullCell() => const PlainValue.nothing(),
  FlagCell(:final value) => PlainValue.flag(value),
  NumberCell(:final value) => PlainValue.number(value),
  TextCell(:final text) => PlainValue.text(text),
  BytesCell(:final bytes) => PlainValue.bytes(bytes),
  ListCell(:final items, :final raw) => PlainValue.list(
    items: [for (final x in items) _plainOf(x)].lock,
    raw: raw,
  ),
  MapCell(:final entries, :final raw) => PlainValue.map(
    entries: [
      for (final e in entries)
        PlainEntry(key: e.key, textKey: true, value: _plainOf(e.value)),
    ].lock,
    raw: raw,
  ),
  OtherCell(:final text, :final raw) => PlainValue.other(
    text: text,
    type: raw.runtimeType.toString(),
    raw: raw,
  ),
};

/// [t]'s rows as the CSV writer reads them.
List<List<PlainValue>> _plainRows(TableDataVm t) => [
  for (final r in t.rows) [for (final c in r) _plainOf(c)],
];

/// How the viewers read and write tables: a date of the time column `t`,
/// Copy as CSV with a comma and a header, and `table_from_csv`'s own CSV
/// rules for the "As table" tab (docs/studio.md §6.8).
final viewerTables = ViewerTables(
  cellText: (column, cell) => switch (cell) {
    NumberCell(:final value) => tableCellText(column, value),
    _ => null,
  },
  readJson: (text) => switch (plainJsonOf(text)) {
    final v? => cellVmOf(v),
    null => null,
  },
  copyCsv: (t) => writeCsv(t.columns, _plainRows(t)),
  readCsv: _readCsv,
  writeCsv: (t, rules) => writeCsv(
    t.columns,
    _plainRows(t),
    delimiter: rules.delimiter,
    header: rules.header,
  ),
);

/// The last CSV text read, by its rules, and what it gave: the viewer reads
/// it again on every build, and a text may hold 512 KiB.
(String, ViewerCsvVm, TableDataVm?)? _lastCsv;

TableDataVm? _readCsv(String text, ViewerCsvVm rules) {
  if (_lastCsv
      case (
        final t,
        final r,
        final got,
      )
      when t == text && r == rules) {
    return got;
  }
  final got = switch (parseCsv(
    text,
    delimiter: rules.delimiter,
    header: rules.header,
  )) {
    final t? => TableDataVm(t.columns, [
      for (final r in t.rows) [for (final c in r) cellVmOf(c)],
    ]),
    null => null,
  };
  _lastCsv = (text, rules, got);
  return got;
}

/// The mark of a sample's [q]uality, as the Explorer writes it.
QualityMarkVm qualityMarkOf(Quality q) => switch (q) {
  Quality.good => const QualityMarkVm(label: 'good', tone: .good),
  Quality.uncertain => const QualityMarkVm(
    label: 'uncertain',
    tone: .warn,
    mark: .ring,
  ),
  Quality.bad => const QualityMarkVm(label: 'bad', tone: .bad),
};

/// [v] (a map, a list or a scalar) as a tree of nodes; [key] is its key
/// in its map. Bytes inside a structure are a list of numbers.
JsonNodeVm jsonNode(PlainValue v, {String? key}) => switch (v) {
  PlainValueMap(:final entries) => JsonNodeVm(
    key: key,
    kind: .object,
    text: S.current.sizeKeys(entries.length),
    children: [for (final e in entries) jsonNode(e.value, key: e.key)],
  ),
  PlainValueList(:final items) => _array(key, [
    for (final x in items) jsonNode(x),
  ]),
  PlainValueBytes(:final bytes) => _array(key, [
    for (final x in bytes) JsonNodeVm(kind: .number, text: _encode(x)),
  ]),
  PlainValueNothing() => JsonNodeVm(key: key, kind: .nil, text: 'null'),
  PlainValueFlag(:final value) => JsonNodeVm(
    key: key,
    kind: .flag,
    text: '$value',
  ),
  PlainValueNumber(:final value) => JsonNodeVm(
    key: key,
    kind: .number,
    text: _encode(value),
  ),
  PlainValueText(:final text) => JsonNodeVm(
    key: key,
    kind: .string,
    text: jsonEncode(text),
  ),
  PlainValueOther(:final text) => JsonNodeVm(
    key: key,
    kind: .string,
    text: jsonEncode(text),
  ),
};

/// An array of [children]; [key] is its key in its map.
JsonNodeVm _array(String? key, List<JsonNodeVm> children) => JsonNodeVm(
  key: key,
  kind: .array,
  text: S.current.sizeItems(children.length),
  children: children,
);

/// [b] as rows of a hex dump: `00000010  48 65 6c …  Hel…`, at most
/// [_maxBytes], then how many more there are.
List<String> hexRows(Uint8List b) {
  final shown = b.length > _maxBytes ? _maxBytes : b.length;
  return [
    for (var at = 0; at < shown; at += 16)
      () {
        final row = b.sublist(at, at + 16 > shown ? shown : at + 16);
        final hex = [
          for (final x in row) x.toRadixString(16).padLeft(2, '0'),
        ].join(' ');
        final text = String.fromCharCodes([
          for (final x in row)
            if (x >= 0x20 && x < 0x7f) x else 0x2e,
        ]);
        return '${at.toRadixString(16).padLeft(8, '0')}  '
            '${hex.padRight(47)}  $text';
      }(),
    if (b.length > shown) S.current.moreBytes(b.length - shown),
  ];
}

/// A text that is a JSON map or list, decoded; null otherwise.
PlainValue? _json(String t) {
  final x = t.trimLeft();
  if (!x.startsWith('{') && !x.startsWith('[')) {
    return null;
  }
  return switch (plainJsonOf(t)) {
    final PlainValueMap m => m,
    final PlainValueList l => l,
    _ => null,
  };
}

/// [v] as indented JSON; what JSON cannot hold (a map with keys that
/// are not texts, NaN) as Dart writes it.
String _pretty(PlainValue v) => _jsonable(v)
    ? const JsonEncoder.withIndent('  ', _encodable).convert(v.raw)
    : '${v.raw}';

/// Whether JSON holds [v] as it is: keys are texts, numbers are finite.
bool _jsonable(PlainValue v) => switch (v) {
  PlainValueMap(:final entries) => entries.every(
    (e) => e.textKey && _jsonable(e.value),
  ),
  PlainValueList(:final items) => items.every(_jsonable),
  PlainValueNumber(:final value) => value.isFinite,
  _ => true,
};

/// What the encoder cannot write itself, as its text (bytes are a list to
/// it, a list of numbers).
Object? _encodable(Object? v) => '$v';

String _encode(num n) =>
    n is double && (n.isNaN || n.isInfinite) ? jsonEncode('$n') : jsonEncode(n);
