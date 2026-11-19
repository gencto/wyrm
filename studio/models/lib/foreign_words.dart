import 'package:freezed_annotation/freezed_annotation.dart';

part 'foreign_words.freezed.dart';

/// The words of a failure that another package raised in its own words (a
/// plain `UserException` of a library): shown as they came. Studio words
/// none of its own failures this way: those are typed.
@freezed
abstract class ForeignWords with _$ForeignWords {
  const factory ForeignWords({
    /// What it says happened.
    required String title,

    /// What it says beside that; empty when nothing.
    @Default('') String detail,
  }) = _ForeignWords;
}
