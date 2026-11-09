import 'dart:convert';
import 'dart:typed_data';

import 'package:business/wyrm/mappers/value_text.dart';
import 'package:localization/localization.dart';
import 'package:models/quality.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/trees/json_tree.dart';

/// Bytes a viewer dumps as hex; the rest is counted (16 a row).
const int _maxBytes = 16 * 1024;

/// The viewer of a value (a flow field's, a point's): [value] as a live
/// value holds it, drawn by its type (docs/studio.md §6.8).
///
/// - a map or a list, or a text that is a JSON map or list: a tree;
/// - a text: numbered lines;
/// - a number with its [unit] (an enum by its name in [choices]);
/// - a bool: a mark and its word;
/// - `Uint8List` alone is binary (a JSON list of ints stays a list): hex;
/// - nothing known ([known] false): `no value`.
///
/// `copy` of the result is the raw value as JSON, a text as itself.
ValueViewerVm valueViewerOf({
  required String title,
  required Object? value,
  bool known = true,
  String? unit,
  List<String> choices = const [],
  QualityMarkVm? quality,
}) {
  final s = S.current;
  if (!known) {
    return ValueViewerVm(
      title: title,
      type: '—',
      content: EmptyContentVm(s.noValue),
      copy: '',
      quality: quality,
    );
  }
  switch (value) {
    case null:
      return ValueViewerVm(
        title: title,
        type: 'null',
        content: const EmptyContentVm('null'),
        copy: 'null',
        quality: quality,
      );
    case final Uint8List b:
      return ValueViewerVm(
        title: title,
        type: 'bytes',
        size: s.sizeBytes(b.length),
        content: BytesContentVm(hexRows(b)),
        copy: [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join(),
        quality: quality,
      );
    case final Map<Object?, Object?> m:
      return ValueViewerVm(
        title: title,
        type: 'map',
        size: s.sizeKeys(m.length),
        content: JsonContentVm(jsonNode(m)),
        copy: _pretty(m),
        quality: quality,
      );
    case final List<Object?> l:
      return ValueViewerVm(
        title: title,
        type: 'list',
        size: s.sizeItems(l.length),
        content: JsonContentVm(jsonNode(l)),
        copy: _pretty(l),
        quality: quality,
      );
    case final String t:
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
    case final bool b:
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
    case final num n:
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
    default:
      final t = '$value';
      return ValueViewerVm(
        title: title,
        type: value.runtimeType.toString(),
        size: s.sizeChars(t.length),
        content: TextContentVm(t.split('\n')),
        copy: t,
        quality: quality,
      );
  }
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
/// in its map.
JsonNodeVm jsonNode(Object? v, {String? key}) => switch (v) {
  final Map<Object?, Object?> m => JsonNodeVm(
    key: key,
    kind: .object,
    text: S.current.sizeKeys(m.length),
    children: [for (final e in m.entries) jsonNode(e.value, key: '${e.key}')],
  ),
  final List<Object?> l => JsonNodeVm(
    key: key,
    kind: .array,
    text: S.current.sizeItems(l.length),
    children: [for (final x in l) jsonNode(x)],
  ),
  null => JsonNodeVm(key: key, kind: .nil, text: 'null'),
  final bool b => JsonNodeVm(key: key, kind: .flag, text: '$b'),
  final num n => JsonNodeVm(key: key, kind: .number, text: _encode(n)),
  final String t => JsonNodeVm(key: key, kind: .string, text: jsonEncode(t)),
  _ => JsonNodeVm(key: key, kind: .string, text: jsonEncode('$v')),
};

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
Object? _json(String t) {
  final x = t.trimLeft();
  if (!x.startsWith('{') && !x.startsWith('[')) {
    return null;
  }
  try {
    return switch (jsonDecode(t)) {
      final Map<Object?, Object?> m => m,
      final List<Object?> l => l,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// [v] as indented JSON; what JSON cannot hold (a map with keys that
/// are not texts, NaN) as Dart writes it.
String _pretty(Object v) => _jsonable(v)
    ? const JsonEncoder.withIndent('  ', _encodable).convert(v)
    : '$v';

/// Whether JSON holds [v] as it is: keys are texts, numbers are finite.
bool _jsonable(Object? v) => switch (v) {
  final Map<Object?, Object?> m => m.entries.every(
    (e) => e.key is String && _jsonable(e.value),
  ),
  final List<Object?> l => l.every(_jsonable),
  final double d => d.isFinite,
  _ => true,
};

Object? _encodable(Object? v) => switch (v) {
  final Uint8List b => base64Encode(b),
  _ => '$v',
};

String _encode(num n) => n is double && (n.isNaN || n.isInfinite)
    ? jsonEncode('$n')
    : jsonEncode(n);
