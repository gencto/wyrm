import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import 'field_word.dart';

/// Why a row does not take a wire dragged over it (spec §4), said on the
/// canvas beside the pointer.
sealed class BindRefusalVm extends Equatable {
  const BindRefusalVm();

  String get label;

  @override
  List<Object?> get props => [];
}

/// The row is an output: it takes nothing.
final class RefuseOutput extends BindRefusalVm {
  const RefuseOutput();

  @override
  String get label => S.current.refuseOutput;
}

/// The field [field] has no input: its value is typed.
final class RefuseNoInput extends BindRefusalVm {
  const RefuseNoInput(this.field, {this.word});

  /// The field's label when it is data; [word] when it is Studio's word.
  final String field;
  final FieldWordVm? word;

  @override
  String get label => S.current.refuseNoInput(word?.text ?? field);

  @override
  List<Object?> get props => [field, word];
}

/// A block cannot feed itself.
final class RefuseSelf extends BindRefusalVm {
  const RefuseSelf();

  @override
  String get label => S.current.refuseSelf;
}

/// What comes out ([from], an engine type name) does not fit what goes in
/// ([to]).
final class RefuseType extends BindRefusalVm {
  const RefuseType(this.from, this.to);

  final String from;
  final String to;

  @override
  String get label => S.current.refuseType(from, to);

  @override
  List<Object?> get props => [from, to];
}

/// The wire would close a loop.
final class RefuseLoop extends BindRefusalVm {
  const RefuseLoop();

  @override
  String get label => S.current.refuseLoop;
}

/// This broker cannot bind [field] (its engine is older).
final class RefuseNeedsBroker extends BindRefusalVm {
  const RefuseNeedsBroker(this.field, {this.word});

  /// The field's label when it is data; [word] when it is Studio's word.
  final String field;
  final FieldWordVm? word;

  @override
  String get label => S.current.refuseNeedsBroker(word?.text ?? field);

  @override
  List<Object?> get props => [field, word];
}
