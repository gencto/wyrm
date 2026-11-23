import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/approval.dart';
import 'package:business/wyrm/holds.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/agent_task.dart';
import 'package:models/approval_refusal.dart';
import 'package:models/task_state.dart';

/// The two halves of the decision about a plan that waits, read from one
/// place (`selectors.dart`): what the card says (`approvalNote`) and why
/// Approve is held (`approveHold`), in the same order.
void main() {
  const task = AgentTask(
    id: 't-1',
    state: TaskState.awaitingApproval,
    owner: 'user:olena',
    recorded: true,
  );
  final choices = [
    const StepChoice(n: 1, ticked: true),
    const StepChoice(n: 2, byAgent: true),
    const StepChoice(n: 3, byAgent: true, needs: 9),
  ];

  _Read at({
    bool docs = true,
    String? viewed,
    String? refusal,
  }) {
    final a = AppState.initial();
    return _Read(
      a.copyWith(
        site: a.site.copyWith(
          name: 'central',
          current: viewed,
          role: 'engineer',
        ),
        assistant: a.assistant.copyWith(
          docs: docs,
          refusals: refusal == null
              ? const IMapConst({})
              : {'t-1': ApprovalRefusal.said(refusal)}.lock,
        ),
      ),
    );
  }

  test('a gateway without doc comes first, before another site', () {
    final r = at(docs: false, viewed: 'plant', refusal: 'no');
    expect(r.approvalNote(task, choices), isA<ApprovalNoRecord>());
    expect(r.approveHold(task, choices), isA<HoldNoRecord>());
  });

  test('another site comes before a refusal', () {
    final r = at(viewed: 'plant', refusal: 'no');
    expect(
      r.approvalNote(task, choices),
      isA<ApprovalOtherSite>().having((n) => n.site, 'site', 'plant'),
    );
    expect(r.approveHold(task, choices), isA<HoldOtherSite>());
  });

  test('a refusal is said; the task still waits', () {
    final r = at(refusal: 'step 2 needs config');
    expect(
      r.approvalNote(task, choices),
      isA<ApprovalRefused>().having(
        (n) => n.why,
        'why',
        const ApprovalRefusal.said('step 2 needs config'),
      ),
    );
  });

  test('a record not read yet', () {
    expect(
      at().approvalNote(task.copyWith(recorded: false), choices),
      isA<ApprovalWaiting>(),
    );
  });

  test('else what Approve signs, with the changes the agent runs itself', () {
    expect(
      at().approvalNote(task, choices),
      isA<ApprovalSigns>()
          .having((n) => n.role, 'role', 'engineer')
          // the step that needs a skipped one does not run
          .having((n) => n.byAgent, 'byAgent', 1),
    );
  });
}

final class _Read with Selectors, NothingInFlight {
  _Read(this.state);

  @override
  final AppState state;
}
