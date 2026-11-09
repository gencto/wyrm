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
