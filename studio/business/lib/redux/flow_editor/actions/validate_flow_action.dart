import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_problem_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/decode/flow_check.dart';
import '../../../wyrm/decode/flow_def.dart';
import '../../../wyrm/mappers/flow_problems.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `dataflows` ▸ `validate {def}` (read) on the draft as it is drawn,
/// debounced: the problems shown in the editor are the engine's own.
///
/// Edits start it without waiting for it, so two checks may be in flight
/// at once: an answer is kept only while the flow it checked is still the
/// one drawn (its layout aside); an older answer that comes last is
/// dropped, and the newer check's answer stands.
class ValidateFlowAction extends Action with Debounce {
  @override
  int get debounce => 400;

  @override
  Future<AppState?> reduce() async {
    // The flow itself, also while the canvas shows the inside of a block.
    final d = flowEditor.root;
    final root = site.root;
    if (d == null || root == null) {
      return null;
    }
    if (d.id.isEmpty) {
      return state.copyWith.flowEditor(problems: unnamedFlowProblems);
    }
    try {
      final rows = await deps.wyrm
          .invoke(
            '$root/dataflows',
            'validate',
            defArgs(defOf(d, flowEditor.version + 1)),
          )
          .toList();
      if (!_stillDrawn(d)) {
        return null;
      }
      final ids = d.blocks.keys;
      // An answer Studio cannot read goes to the log with its field.
      final check = flowCheckOf(rows)..orWarn('validate ${d.id}');
      return state.copyWith.flowEditor(
        problems: switch (check) {
          Valid(value: FlowCheck(ok: true)) => const IListConst([]),
          Valid(value: FlowCheck(:final error)) => [
            brokerProblem(error, ids),
          ].lock,
          Invalid() => const IListConst([
            FlowProblem(kind: FlowProblemKind.unread),
          ]),
        },
      );
    } on WyrmException catch (e) {
      if (!_stillDrawn(d)) {
        return null;
      }
      return state.copyWith.flowEditor(
        problems: [brokerProblem(e.message, d.blocks.keys)].lock,
      );
    }
  }

  /// The flow [checked] is still the one drawn, its layout aside.
  bool _stillDrawn(FlowDraft checked) => switch (flowEditor.root) {
    final now? =>
      identical(now, checked) || previewDefOf(now) == previewDefOf(checked),
    null => false,
  };
}
