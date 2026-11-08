import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_draft.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../models/flow_editor_state.dart';

/// Opens [id] in the editor: the block catalogue (`dataflows` ▸
/// `node_types`) and the newest definition (`dataflows/<id>` ▸ `history`);
/// a new flow starts empty.
class LoadFlowAction extends Action {
  LoadFlowAction(this.id, {this.isNew = false});

  final String id;
  final bool isNew;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final cat = await invokeOne(api, '$root/dataflows', 'node_types');
    final types =
        [
          if (cat case VArray(:final v))
            for (final t in v) nodeTypeOf(t),
        ]..sort(
          (a, b) => a.category == b.category
              ? a.type.compareTo(b.type)
              : a.category.compareTo(b.category),
        );
    var draft = FlowDraft(id: id);
    if (!isNew) {
      final defs = await invokeOne(api, '$root/dataflows/$id', 'history');
      if (defs case VArray(:final v) when v.isNotEmpty) {
        draft = tidyIfOverlapping(
          flowDraftOf(id, v.last),
          {for (final t in types) t.type: t},
        );
      }
    }
    return state.copyWith(
      flowEditor: FlowEditorState(
        flowId: id,
        draft: draft,
        version: draft.version,
        types: types.lock,
      ),
    );
  }
}
