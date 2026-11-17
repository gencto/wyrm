import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/flow_draft.dart';
import 'package:models/library_off.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/decode/flow_def.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_layout.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/retrieve_block_types_action.dart';
import '../../flows/actions/retrieve_flows_action.dart';
import '../models/flow_editor_state.dart';
import 'unload_flow_action.dart';

/// Opens [id] in the editor: the block catalogue (`dataflows` ▸
/// `node_types`, from the session's cache `flows.blockTypes` when it holds
/// one) and the newest definition (`dataflows/<id>` ▸ `history`); a new flow
/// starts empty. A draft of the same flow that differs from the deployed
/// version is kept (closing the editor does not drop it) unless the broker
/// has a newer version.
///
/// A person may open one flow and then another before the first answered,
/// and the watch of a redeployed flow reads the flow on screen again
/// ([LoadFlowAction.redeployed]) without anyone waiting: no load waits for
/// another, and the answer of a load that was replaced is dropped whole
/// ([replaced]: no state, no unload, no error said).
/// - An open is replaced by an open started after it (the flow opened last
///   is the one that stays, whichever answers first) and by a later read
///   of the same flow after a redeploy (that read is the newer one).
/// - A read after a redeploy is replaced by any open started after it, by
///   a later read of the same flow, and when the editor holds another
///   flow by the time it answers. It never replaces an open of another
///   flow.
/// - Both are replaced when the site was left.
class LoadFlowAction extends Action {
  LoadFlowAction(this.id, {this.isNew = false, this.route})
    : redeployed = false;

  /// The flow on screen was deployed again: its newest version is read.
  LoadFlowAction.redeployed(this.id)
    : isNew = false,
      route = null,
      redeployed = true;

  @override
  Action again() => redeployed
      ? LoadFlowAction.redeployed(id)
      : LoadFlowAction(id, isNew: isNew, route: route);

  @override
  Action reload() => RetrieveFlowsAction();

  final String id;
  final bool isNew;

  /// The editor's route, kept with the flow (null: the one it has).
  final String? route;

  /// The read of the flow on screen after a redeploy, not an open.
  final bool redeployed;

  /// What this load asked and its place among the loads: the site, the
  /// open and the redeploy read of this flow started last when it began
  /// (one of the two is its own). Null before it asked.
  ({String root, int open, int reread})? _asked;

  /// The answer of this load was dropped: another load took its place, or
  /// the site was left. Who started it does nothing more for it.
  bool get replaced => _replaced;
  var _replaced = false;

  Object get _rereads => (LoadFlowAction, id);

  /// Another load took this one's place, as the order stands now.
  bool get _isReplaced {
    final asked = _asked;
    if (asked == null) {
      return false;
    }
    final latest = deps.latest;
    return site.root != asked.root ||
        latest.started(LoadFlowAction) != asked.open ||
        latest.started(_rereads) != asked.reread ||
        (redeployed && flowEditor.flowId != id);
  }

  /// A failure of a load that was replaced is not said: the screen shows
  /// another flow, whose load says its own.
  @override
  Object? wrapError(Object error, StackTrace stackTrace) {
    if (_isReplaced) {
      _replaced = true;
      return null;
    }
    return super.wrapError(error, stackTrace);
  }

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final latest = deps.latest;
    _asked = redeployed
        ? (
            root: root,
            open: latest.started(LoadFlowAction),
            reread: latest.start(_rereads),
          )
        : (
            root: root,
            open: latest.start(LoadFlowAction),
            reread: latest.started(_rereads),
          );
    final api = deps.wyrm;
    // The catalogue is read once per session and site (`flows.blockTypes`,
    // filled by the log-in preload); only a cold cache asks the broker.
    final cached = flows.blockTypes;
    final types = cached.isNotEmpty ? cached : await readBlockTypes(api, root);
    final key = '$root/dataflows/$id';
    final history = isNew ? null : await askOne(api, key, 'history');
    // Every `await` is behind, and nothing was written yet: a load that was
    // replaced ends here, before it reads the editor, unloads a flow or
    // says that its definition does not read.
    if (_isReplaced) {
      _replaced = true;
      return null;
    }
    var draft = FlowDraft(id: id);
    if (history != null) {
      final read = switch (newestFlowOf(id, history)) {
        Valid(:final value) => value,
        // A definition Studio cannot read is said, with the field. The
        // same flow keeps what it had; another flow drops the one held
        // (so it is not drawn or deployed under this id) and gets no
        // draft: never an empty one a deploy would write over the flow.
        Invalid(:final field, :final reason) => throw _unreadable(
          key,
          '$field: $reason',
        ),
      };
      if (read != null) {
        // A saved place always wins; blocks without one are laid out by
        // the data flow (flow-editor.md §25).
        draft = placeFlow(
          read.draft,
          // The catalog with the flow's own custom blocks, as drawn.
          {for (final t in typesWithBlocks(types, read.draft)) t.type: t},
          placed: read.placed.unlock,
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
    // A draft kept while the canvas showed the inside of a block: the
    // flow with that inside folded back.
    final shown = keep ? rootDraft(held.frames, held.draft)! : draft;
    // The same flow read again (a redeploy) keeps its selection and, with
    // its draft, the draft's history.
    final selection = held.flowId == id
        ? held.selection.removeWhere((b) => !shown.blocks.containsKey(b))
        : const ISetConst<String>({});
    return state.copyWith(
      flows: state.flows.copyWith(blockTypes: types),
      flowEditor: FlowEditorState(
        flowId: id,
        route: route ?? held.route,
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
        treeQuery: held.treeQuery,
        // The library is read after the flow (`RetrieveBlockLibraryAction`);
        // until it answers, custom blocks are off.
        library: held.library,
        libraryOff: held.flowId == null
            ? const LibraryOff.unread()
            : held.libraryOff,
      ),
    );
  }

  /// Why flow [id] does not open; another flow held before goes first
  /// (that state is the one the screen keeps, so it is drawn).
  StudioException _unreadable(String key, String why) {
    if (flowEditor.flowId != id) {
      dispatchSync(UnloadFlowAction(id));
    }
    return StudioException.hinted(
      ErrorKind.broker,
      ErrorHint.flowDefInvalid(flow: id, why: why),
      key: key,
      call: const .known(.history),
      thing: id,
    );
  }
}
