import 'dart:convert';

/// A live value (as `LiveValue.value` holds it) as the user reads it.
///
/// - An enum (spec 02 key 3: `~val.v` is the index into [choices]) shows its
///   name; an index out of range shows the number.
/// - A number is rounded for reading (3 decimals, 1 from 100 up, no trailing
///   zeros) and followed by [unit]. A unit is written after a number only,
///   never after an enum, a bool or a text (spec 02 key 2).
/// - A map or a list is JSON; null is `null`.
String valueText(
  Object? value, {
  List<String> choices = const [],
  String? unit,
}) {
  if (choices.isNotEmpty) {
    final i = switch (value) {
      final int n => n,
      final double d when d == d.truncateToDouble() => d.toInt(),
      _ => null,
    };
    if (i != null && i >= 0 && i < choices.length) {
      return choices[i];
    }
    if (value is num) {
      return _number(value);
    }
  }
  final s = switch (value) {
    null => 'null',
    final num n => _number(n),
    final Map<String, Object?> m => jsonEncode(m),
    final List<Object?> l => jsonEncode(l),
    _ => '$value',
  };
  return value is num && choices.isEmpty && unit != null && unit.isNotEmpty
      ? '$s $unit'
      : s;
}

String _number(num n) => switch (n) {
  final int i => '$i',
  final double d when d.isNaN || d.isInfinite => '$d',
  final double d =>
    d
        .toStringAsFixed(d.abs() >= 100 ? 1 : 3)
        .replaceFirst(RegExp(r'\.?0+$'), ''),
};

/// A date value of the flow engine (microseconds since the Unix epoch, ADR
/// 0044 §3) as the user reads it: the local wall time of this computer,
/// `2026-11-11 12:29:03`, with the milliseconds when it has them. Null for
/// a value that is no whole number or no date.
String? dateText(Object? micros) {
  final us = switch (micros) {
    final int i => i,
    final double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
    _ => null,
  };
  // 10 000 years either way: a larger number is no date.
  if (us == null || us.abs() > 315537897600000000) {
    return null;
  }
  final t = DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = t.millisecond == 0
      ? ''
      : '.${t.millisecond.toString().padLeft(3, '0')}';
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}$ms';
}

/// The same instant in UTC, ISO 8601 (`2026-11-11T10:29:03Z`), for the
/// value viewer beside [dateText].
String? dateTextUtc(Object? micros) {
  final local = dateText(micros);
  if (local == null) {
    return null;
  }
  final t = DateTime.fromMicrosecondsSinceEpoch(
    (micros! as num).toInt(),
    isUtc: true,
  );
  return '${t.toIso8601String().split('.').first}Z';
}
