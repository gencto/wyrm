import 'package:ui/models/query.dart';

/// A question answered by a function, for a test or a board: its key is
/// the function itself (one answer per instance).
final class TestQuery<Q, A> extends QueryVm<Q, A> {
  TestQuery(A Function(Q question) answer)
    : _answer = ((question) => answer(question as Q));

  final A Function(Object? question) _answer;

  @override
  Object? get key => _answer;

  @override
  A ask(Q question) => _answer(question);
}
