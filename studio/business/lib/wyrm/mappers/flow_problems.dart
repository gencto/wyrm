import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_problem_kind.dart';

/// The block a problem's [text] names: the longest of [ids] it holds as a
/// word (`scale1: unknown input` names `scale1`, not `scale`). Null when it
/// names none.
String? blockNamedIn(String text, Iterable<String> ids) {
  String? best;
  for (final id in ids) {
    final hit = RegExp(
      '(^|[^A-Za-z0-9_])${RegExp.escape(id)}([^A-Za-z0-9_]|\$)',
    ).hasMatch(text);
    if (hit && (best == null || id.length > best.length)) {
      best = id;
    }
  }
  return best;
}

/// The broker's [message] on a flow whose blocks are [ids], with the block
/// it names.
FlowProblem brokerProblem(String? message, Iterable<String> ids) => FlowProblem(
  kind: FlowProblemKind.broker,
  message: message,
  block: message == null ? null : blockNamedIn(message, ids),
);

/// The problems of a new flow with no name yet.
const IList<FlowProblem> unnamedFlowProblems = IListConst([
  FlowProblem(kind: FlowProblemKind.unnamed),
]);
