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
/// a new flow starts empty. A draft of the same flow that differs from the
/// deployed version is kept (closing the editor does not drop it) unless
/// the broker has a newer version.
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
    final held = flowEditor;
    final keep =
        !isNew &&
        held.flowId == id &&
        held.dirty &&
        held.draft != null &&
        held.version == draft.version;
    return state.copyWith(
      flowEditor: FlowEditorState(
        flowId: id,
        draft: keep ? held.draft : draft,
        dirty: keep,
        deployed: isNew ? null : draft,
        version: draft.version,
        types: types.lock,
        palette: held.palette,
        // The same flow read again (a redeploy) keeps its selection.
        selectedBlock:
            held.flowId == id &&
                (keep ? held.draft : draft)!.blocks.containsKey(
                  held.selectedBlock,
                )
            ? held.selectedBlock
            : null,
      ),
    );
  }
}
