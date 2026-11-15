import 'package:equatable/equatable.dart';

/// A question a widget asks at the moment the user acts, answered from the
/// state then: what a context menu shows where it opened, what a dialog
/// proposes, why a typed value is refused. A view-model cannot hold these
/// answers ahead of time (one per place, per selection, per keystroke), so
/// it holds the question's answer function instead.
///
/// [A] is a `ui` type (an enum that words itself, a render model), never
/// text built outside `ui`. [key] is what the answers depend on: a new key
/// rebuilds the widget, the same key is the same answers (the equality rule
/// of value_changed.dart: the function is behaviour, not data).
final class QueryVm<Q, A> extends Equatable {
  QueryVm(A Function(Q question) ask, {this.key})
    // The question's type is kept in [ask]'s own signature: held as
    // `Object?` here, so `Q` stays out of a field's parameter position.
    : _ask = ((question) => ask(question as Q));

  final A Function(Object? question) _ask;

  /// What the answers depend on.
  final Object? key;

  /// The answer to [question] now.
  A ask(Q question) => _ask(question);

  @override
  List<Object?> get props => [key];
}
