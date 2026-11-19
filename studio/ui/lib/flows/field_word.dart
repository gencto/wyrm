import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

/// A word Studio has of its own for a field of a block (flow-editor.md
/// §3): said here, in the language on screen (studio-rules §5).
enum FieldWordTag {
  input,
  output,
  trigger,
  inputOutOfRange,
  factor,
  offset,
  absoluteChange,
  percentChange,
  function,
  operation,
  expression,
  message,
  delayMs,
  point,
  valueName,
  meta,
  allowBadQuality,
  onBadQuality,
  maxSamples,
  memoryMb,
  every,
  autoRun,
  runOnStart,
  scope,
  resetMode,
  node,
  writeOn,
  runOn,
  intervalS,
  periodMs,
  quietTimeMs,
  delimiter,
  alive,
  result,
  average,
  active,
  count,
  value,
  runWhen,
  caseOf,
  then;

  String get label {
    final s = S.current;
    return switch (this) {
      input => s.fieldWordInput,
      output => s.fieldWordOutput,
      trigger => s.fieldWordTrigger,
      inputOutOfRange => s.fieldWordInputOutOfRange,
      factor => s.fieldWordFactor,
      offset => s.fieldWordOffset,
      absoluteChange => s.fieldWordAbsoluteChange,
      percentChange => s.fieldWordPercentChange,
      function => s.fieldWordFunction,
      operation => s.fieldWordOperation,
      expression => s.fieldWordExpression,
      message => s.fieldWordMessage,
      delayMs => s.fieldWordDelayMs,
      point => s.fieldWordPoint,
      valueName => s.fieldWordValueName,
      meta => s.fieldWordMeta,
      allowBadQuality => s.fieldWordAllowBadQuality,
      onBadQuality => s.fieldWordOnBadQuality,
      maxSamples => s.fieldWordMaxSamples,
      memoryMb => s.fieldWordMemoryMb,
      every => s.fieldWordEvery,
      autoRun => s.fieldWordAutoRun,
      runOnStart => s.fieldWordRunOnStart,
      scope => s.fieldWordScope,
      resetMode => s.fieldWordResetMode,
      node => s.fieldWordNode,
      writeOn => s.fieldWordWriteOn,
      runOn => s.fieldWordRunOn,
      intervalS => s.fieldWordIntervalS,
      periodMs => s.fieldWordPeriodMs,
      quietTimeMs => s.fieldWordQuietTimeMs,
      delimiter => s.fieldWordDelimiter,
      alive => s.fieldWordAlive,
      result => s.fieldWordResult,
      average => s.fieldWordAverage,
      active => s.fieldWordActive,
      count => s.fieldWordCount,
      value => s.fieldWordValue,
      runWhen => s.fieldWordRunWhen,
      caseOf => s.fieldWordCaseOf,
      then => s.fieldWordThen,
    };
  }
}

/// A field's label when it is Studio's own word: the [word], alone or
/// with its number [n] (`Input 1`, `Case 2`).
final class FieldWordVm extends Equatable {
  const FieldWordVm(this.word, [this.n]);

  final FieldWordTag word;
  final int? n;

  String get text => switch (n) {
    final n? => S.current.fieldNumbered(word.label, n),
    null => word.label,
  };

  @override
  List<Object?> get props => [word, n];
}
