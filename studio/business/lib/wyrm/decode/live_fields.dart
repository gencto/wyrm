import 'decoded.dart';

// One field of a live value (the plain Dart value the live service holds:
// null, bool, int, double, String, `List<Object?>`, `Map<String,
// Object?>`), decoded to its type. A field that has not arrived (null) is
// a valid absence; a value of another shape is [Invalid] with its field.

/// A number.
Decoded<num?> liveNumber(Object? v, String shape, String field) => switch (v) {
  null => const Valid(null),
  final num n => Valid(n),
  _ => Invalid(shape, field, 'not a number'),
};

/// A whole number (a whole float too).
Decoded<int?> liveInt(Object? v, String shape, String field) => switch (v) {
  null => const Valid(null),
  final int n => Valid(n),
  final double d when d == d.truncateToDouble() => Valid(d.toInt()),
  _ => Invalid(shape, field, 'not a whole number'),
};

/// A text.
Decoded<String?> liveText(Object? v, String shape, String field) => switch (v) {
  null => const Valid(null),
  final String s => Valid(s),
  _ => Invalid(shape, field, 'not a text'),
};

/// A moment written as ISO 8601 text (empty: none).
Decoded<DateTime?> liveTime(Object? v, String shape, String field) =>
    switch (v) {
      null || '' => const Valid(null),
      final String s => switch (DateTime.tryParse(s)) {
        final t? => Valid(t),
        null => Invalid(shape, field, 'not an ISO 8601 time'),
      },
      _ => Invalid(shape, field, 'not a text'),
    };

/// A wire name, read by [fromWire], or a missing value.
Decoded<E?> liveName<E>(
  Object? v,
  E? Function(String wire) fromWire,
  String shape,
  String field,
) => switch (v) {
  null => const Valid(null),
  final String s => switch (fromWire(s)) {
    final e? => Valid(e),
    null => Invalid(shape, field, 'not a known name'),
  },
  _ => Invalid(shape, field, 'not a text'),
};
