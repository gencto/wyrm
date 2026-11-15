import 'package:freezed_annotation/freezed_annotation.dart';

import 'flow_problem_kind.dart';

part 'flow_problem.freezed.dart';

/// What is wrong with the flow being edited, as the editor shows it: the
/// broker's compiler refused it, it has no name yet, or the answer could
/// not be read. The block the problem names (by id, the longest one it
/// holds as a word) is found once, when the answer is read.
@freezed
abstract class FlowProblem with _$FlowProblem {
  const factory FlowProblem({
    required FlowProblemKind kind,

    /// The broker's own words ([FlowProblemKind.broker]); null for the
    /// editor's own problems, which `ui` says in its words.
    String? message,

    /// The block it names; null when it names none.
    String? block,
  }) = _FlowProblem;
}
