import 'package:models/field_label.dart';
import 'package:models/field_word.dart';

/// The English of a field's label, for the tests of `business` that read
/// a block as a person does. The words themselves are `ui`'s, from the
/// `.arb` files (`ui/test/field_words_test.dart` holds the two equal).
extension FieldLabelEn on FieldLabel {
  String get en => switch (this) {
    FieldLabelText(:final text) => text,
    FieldLabelWord(:final word) => word.en,
    FieldLabelNumbered(:final word, :final n) => '${word.en} $n',
  };
}

extension FieldWordEn on FieldWord {
  String get en => switch (this) {
    FieldWord.input => 'Input',
    FieldWord.output => 'Output',
    FieldWord.trigger => 'Trigger',
    FieldWord.inputOutOfRange => 'Input out of range',
    FieldWord.factor => 'Factor',
    FieldWord.offset => 'Offset',
    FieldWord.absoluteChange => 'Absolute change',
    FieldWord.percentChange => 'Percent change',
    FieldWord.function => 'Function',
    FieldWord.operation => 'Operation',
    FieldWord.expression => 'Expression',
    FieldWord.message => 'Message',
    FieldWord.delayMs => 'Delay (ms)',
    FieldWord.point => 'Point',
    FieldWord.valueName => 'Value name',
    FieldWord.meta => 'Meta',
    FieldWord.allowBadQuality => 'Allow bad quality',
    FieldWord.onBadQuality => 'On bad quality',
    FieldWord.maxSamples => 'Max samples',
    FieldWord.memoryMb => 'Memory (MB)',
    FieldWord.every => 'Every',
    FieldWord.autoRun => 'Auto run',
    FieldWord.runOnStart => 'Run on start',
    FieldWord.scope => 'Scope',
    FieldWord.resetMode => 'Reset mode',
    FieldWord.node => 'Node',
    FieldWord.writeOn => 'Write on',
    FieldWord.runOn => 'Run on',
    FieldWord.intervalS => 'Interval (s)',
    FieldWord.periodMs => 'Period (ms)',
    FieldWord.quietTimeMs => 'Quiet time (ms)',
    FieldWord.delimiter => 'Delimiter',
    FieldWord.alive => 'Alive',
    FieldWord.result => 'Result',
    FieldWord.average => 'Average',
    FieldWord.active => 'Active',
    FieldWord.count => 'Count',
    FieldWord.value => 'Value',
    FieldWord.runWhen => 'Run when',
    FieldWord.caseOf => 'Case',
    FieldWord.then => 'Then',
  };
}
