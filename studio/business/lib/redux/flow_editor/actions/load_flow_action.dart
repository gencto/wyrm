import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_draft.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/retrieve_block_types_action.dart';
import '../models/flow_editor_state.dart';

/// Opens [id] in the editor: the block catalogue (`dataflows` ▸
/// `node_types`, from the session's cache `flows.blockTypes` when it holds
/// one) and the newest definition (`dataflows/<id>` ▸ `history`); a new flow
/// starts empty. A draft of the same flow that differs from the deployed
/// version is kept (closing the editor does not drop it) unless the broker
/// has a newer version.
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
    // The catalogue is read once per session and site (`flows.blockTypes`,
    // filled by the log-in preload); only a cold cache asks the broker.
    final cached = flows.blockTypes;
    final types = cached.isNotEmpty ? cached : await readBlockTypes(api, root);
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
    final shown = keep ? held.draft! : draft;
    // The same flow read again (a redeploy) keeps its selection and, with
    // its draft, the draft's history.
    final selection = held.flowId == id
        ? held.selection.removeWhere((b) => !shown.blocks.containsKey(b))
        : const ISetConst<String>({});
    return state.copyWith(
      flows: state.flows.copyWith(blockTypes: types),
      flowEditor: FlowEditorState(
        flowId: id,
        draft: shown,
        dirty: keep,
        deployed: isNew ? null : draft,
        version: draft.version,
        types: types,
        palette: held.palette,
        selection: selection,
        selectedBlock: selection.length == 1 ? selection.single : null,
        undo: keep ? held.undo : const IListConst([]),
        redo: keep ? held.redo : const IListConst([]),
        // Blocks copied in one flow paste into the next one opened.
        clipboard: held.clipboard,
      ),
    );
  }
}
