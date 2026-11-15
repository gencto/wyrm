import 'package:business/wyrm/mappers/flow_problems.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_problem_kind.dart';

/// The block a problem names is found once, in business, when the answer
/// is read (it was the connector's `_blockIn`).
void main() {
  test('the longest block id the text holds as a word', () {
    const ids = ['scale', 'scale1', 'k', 'level'];
    expect(blockNamedIn('scale1: unknown input in.zz', ids), 'scale1');
    expect(blockNamedIn('edge k.out -> level.in: loop', ids), 'level');
    expect(blockNamedIn('nodes.k.type: missing', ids), 'k');
    expect(blockNamedIn('scaled: no such type', ids), isNull);
    expect(blockNamedIn('nothing here', ids), isNull);
    expect(blockNamedIn('a+b', const ['a+b']), 'a+b', reason: 'escaped');
  });

  test("the broker's words, with the block they name", () {
    expect(
      brokerProblem('k: in.x is no input', const ['k', 'kk']),
      const FlowProblem(
        kind: FlowProblemKind.broker,
        message: 'k: in.x is no input',
        block: 'k',
      ),
    );
    expect(
      brokerProblem(null, const ['k']),
      const FlowProblem(kind: FlowProblemKind.broker),
    );
    expect(unnamedFlowProblems.single.kind, FlowProblemKind.unnamed);
  });
}
