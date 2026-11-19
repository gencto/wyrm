import 'package:models/field_label.dart';
import 'package:models/field_word.dart';
import 'package:ui/flows/field_word.dart';

// A field's label as `ui` takes it (studio-rules §3, §5): a text that is
// data goes as it is; a word of Studio's own goes as its tag, and the
// widget says it.

extension FieldWordTagOf on FieldWord {
  FieldWordTag get tag => switch (this) {
    FieldWord.input => .input,
    FieldWord.output => .output,
    FieldWord.trigger => .trigger,
    FieldWord.inputOutOfRange => .inputOutOfRange,
    FieldWord.factor => .factor,
    FieldWord.offset => .offset,
    FieldWord.absoluteChange => .absoluteChange,
    FieldWord.percentChange => .percentChange,
    FieldWord.function => .function,
    FieldWord.operation => .operation,
    FieldWord.expression => .expression,
    FieldWord.message => .message,
    FieldWord.delayMs => .delayMs,
    FieldWord.point => .point,
    FieldWord.valueName => .valueName,
    FieldWord.meta => .meta,
    FieldWord.allowBadQuality => .allowBadQuality,
    FieldWord.onBadQuality => .onBadQuality,
    FieldWord.maxSamples => .maxSamples,
    FieldWord.memoryMb => .memoryMb,
    FieldWord.every => .every,
    FieldWord.autoRun => .autoRun,
    FieldWord.runOnStart => .runOnStart,
    FieldWord.scope => .scope,
    FieldWord.resetMode => .resetMode,
    FieldWord.node => .node,
    FieldWord.writeOn => .writeOn,
    FieldWord.runOn => .runOn,
    FieldWord.intervalS => .intervalS,
    FieldWord.periodMs => .periodMs,
    FieldWord.quietTimeMs => .quietTimeMs,
    FieldWord.delimiter => .delimiter,
    FieldWord.alive => .alive,
    FieldWord.result => .result,
    FieldWord.average => .average,
    FieldWord.active => .active,
    FieldWord.count => .count,
    FieldWord.value => .value,
    FieldWord.runWhen => .runWhen,
    FieldWord.caseOf => .caseOf,
    FieldWord.then => .then,
  };
}

extension FieldLabelUi on FieldLabel {
  /// The label's own text; empty when it is one of Studio's words.
  String get data => switch (this) {
    FieldLabelText(:final text) => text,
    FieldLabelWord() || FieldLabelNumbered() => '',
  };

  /// Studio's word for it; null when the label is data.
  FieldWordVm? get word => switch (this) {
    FieldLabelText() => null,
    FieldLabelWord(:final word) => FieldWordVm(word.tag),
    FieldLabelNumbered(:final word, :final n) => FieldWordVm(word.tag, n),
  };
}
