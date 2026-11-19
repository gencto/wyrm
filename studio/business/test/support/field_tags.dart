import 'package:models/field_label.dart';

/// A field's label as a test of `business` names it: a word Studio words
/// itself by the name of its `FieldWord` with a `#` before it (`#input`,
/// `#input 2`), the engine's own name as it came. The words are `ui`'s
/// (`ui/test/field_words_test.dart`); `business` holds and asserts none.
extension FieldLabelTag on FieldLabel {
  String get tag => switch (this) {
    FieldLabelText(:final text) => text,
    FieldLabelWord(:final word) => '#${word.name}',
    FieldLabelNumbered(:final word, :final n) => '#${word.name} $n',
  };
}
