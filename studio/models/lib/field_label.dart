import 'package:freezed_annotation/freezed_annotation.dart';

import 'field_word.dart';

part 'field_label.freezed.dart';

/// What a field of a block reads: a text that is data (the catalog's own
/// `display`, the engine's name made readable, a point's name, a name its
/// author gave), or a word of Studio's own, alone or numbered (`Input 1`,
/// `Case 2`), which `ui` says in the language on screen.
@freezed
sealed class FieldLabel with _$FieldLabel {
  const factory FieldLabel.text(String text) = FieldLabelText;

  const factory FieldLabel.word(FieldWord word) = FieldLabelWord;

  /// [word] with its number, counted from 1.
  const factory FieldLabel.numbered(FieldWord word, int n) = FieldLabelNumbered;
}
