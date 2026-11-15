import 'package:equatable/equatable.dart';

import '../needs_right.dart';

/// Why a control of the flow editor is off: one of the screen's own
/// reasons (an enum of that control), or a right the user lacks.
sealed class Off<R extends Enum> extends Equatable {
  const Off();
}

/// Off for [reason].
final class OffFor<R extends Enum> extends Off<R> {
  const OffFor(this.reason);

  final R reason;

  @override
  List<Object?> get props => [reason];
}

/// Off: the user lacks [right].
final class OffNeeds<R extends Enum> extends Off<R> {
  const OffNeeds(this.right);

  final NeedsRight right;

  @override
  List<Object?> get props => [right];
}

/// [right] as an [Off], or null when nothing is lacking.
Off<R>? offNeeds<R extends Enum>(NeedsRight? right) =>
    right == null ? null : OffNeeds<R>(right);
