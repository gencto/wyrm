import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/flow_check.dart';
import '../../../wyrm/decode/flow_def.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `dataflows` ▸ `validate {def}` (read) on the draft as it is drawn,
/// debounced: the problems shown in the editor are the engine's own.
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
      return state.copyWith.flowEditor(
        problems: const IListConst(['name the flow']),
      );
    }
    try {
      final rows = await deps.wyrm
          .invoke(
            '$root/dataflows',
            'validate',
            defArgs(defOf(d, flowEditor.version + 1)),
          )
          .toList();
      final check = flowCheckOf(rows).orWarn('validate ${d.id}');
      return state.copyWith.flowEditor(
        problems: check != null && check.ok
            ? const IListConst([])
            : [check?.error ?? 'invalid'].lock,
      );
    } on WyrmException catch (e) {
      return state.copyWith.flowEditor(problems: [e.message].lock);
    }
  }
}
