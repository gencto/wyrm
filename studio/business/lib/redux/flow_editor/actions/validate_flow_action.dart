import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/flow_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `dataflows` ▸ `validate {def}` (read) on the draft as it is drawn,
/// debounced: the problems shown in the editor are the engine's own.
class ValidateFlowAction extends Action with Debounce {
  @override
  int get debounce => 400;

  @override
  Future<AppState?> reduce() async {
    final d = flowEditor.draft;
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
            Value.from({'def': toDart(defOf(d, flowEditor.version + 1))}),
          )
          .toList();
      final r = rows.isEmpty ? const VNull() : rows.first;
      final ok = boolean(r['ok']) ?? false;
      return state.copyWith.flowEditor(
        problems: ok
            ? const IListConst([])
            : [str(r['error']) ?? text(r) ?? 'invalid'].lock,
      );
    } on WyrmException catch (e) {
      return state.copyWith.flowEditor(problems: [e.message].lock);
    }
  }
}
