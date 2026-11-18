import 'package:logging/logging.dart';

/// What a decoder of `business/lib/wyrm/decode/` returns (studio-rules §8):
/// the typed value, or why the wire value is not one, with the field.
///
/// A caller switches on it once, at the edge, and decides there what an
/// [Invalid] value means for it (drop the row, keep the old state, show a
/// fault). Downstream of that switch nothing is a wire value any more.
sealed class Decoded<T> {
  const Decoded();

  /// The value; for an [Invalid] one, null **and a warning** naming the
  /// shape, the field and the reason, with [where] (`flow plant-1`). A
  /// caller that can show the fault switches on [Valid] / [Invalid]
  /// itself; nothing turns an [Invalid] into a silent null.
  T? orWarn(String where) => switch (this) {
    Valid(:final value) => value,
    final Invalid<T> i => _warn<T>(where, i),
  };

  static R? _warn<R>(String where, Invalid<R> i) {
    decodeLog.warning('$where: ${i.shape}.${i.field}: ${i.reason}');
    return null;
  }
}

/// The log a decode failure goes to.
final decodeLog = Logger('wyrm.decode');

/// The wire value is a [T].
final class Valid<T> extends Decoded<T> {
  const Valid(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Valid<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Valid($value)';
}

/// The wire value is not a [T]: [field] of the shape [shape] is [reason].
final class Invalid<T> extends Decoded<T> {
  const Invalid(this.shape, this.field, this.reason);

  /// The shape decoded: `device record`, `flow permissions`.
  final String shape;

  /// The field at fault, by its wire name; empty for the value itself.
  final String field;

  /// `missing`, `not a map`, `not a code or a name`.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is Invalid<T> &&
      other.shape == shape &&
      other.field == field &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(shape, field, reason);

  @override
  String toString() => 'Invalid($shape.$field: $reason)';
}

/// The field of [bad] a screen may name (its wire name); why it does not
/// read is written to the log with [where], never shown: a decoder's
/// reason is a developer's word, not the user's.
String loggedField(String where, Invalid<Object?> bad) {
  decodeLog.warning('$where: ${bad.shape}.${bad.field}: ${bad.reason}');
  return bad.field;
}
