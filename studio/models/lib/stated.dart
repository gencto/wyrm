import 'package:freezed_annotation/freezed_annotation.dart';

part 'stated.freezed.dart';

/// One field of a manifest a person wrote, as the check of it needs it:
/// there and of its type, absent, or of another type (with its text, for
/// the line that says so).
@freezed
sealed class Stated<T> with _$Stated<T> {
  const Stated._();

  /// The field is there and of its type.
  const factory Stated.given(T value) = StatedGiven<T>;

  /// The file has no such field.
  const factory Stated.absent() = StatedAbsent<T>;

  /// The field is of another type; [text] is what the file writes.
  const factory Stated.wrong(String text) = StatedWrong<T>;

  /// The value when it is there and of its type.
  T? get orNull => switch (this) {
    StatedGiven(:final value) => value,
    StatedAbsent() || StatedWrong() => null,
  };

  /// What the file holds, as the file writes it; null when it holds
  /// nothing.
  String? get written => switch (this) {
    StatedGiven(:final value) => '$value',
    StatedAbsent() => null,
    StatedWrong(:final text) => text,
  };
}
