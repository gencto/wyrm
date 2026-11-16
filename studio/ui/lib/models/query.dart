import 'package:equatable/equatable.dart';

/// A question a widget asks at the moment the user acts: what a context
/// menu shows where it opened, why a wire let go here would not bind, why
/// a typed value is refused. The answers cannot be held ahead of time (one
/// per place, per keystroke), so the view-model holds the values they are
/// made of, and [ask] makes an answer from them.
///
/// [key] is required and holds exactly what the answers are made of: two
/// questions with equal keys give the same answers, so a view-model that
/// holds one compares what it really depends on, and a change of it
/// rebuilds. [ask] reads nothing but what [key] holds.
///
/// [A] is a `ui` type (an enum that words itself, a render model), never
/// text built outside `ui`.
abstract base class QueryVm<Q, A> extends Equatable {
  const QueryVm();

  /// What the answers are made of.
  Object? get key;

  /// The answer to [question].
  A ask(Q question);

  @override
  List<Object?> get props => [key];
}
