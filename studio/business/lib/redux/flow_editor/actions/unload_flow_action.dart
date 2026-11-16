import '../../app_state.dart';
import '../../common/action.dart';
import '../models/flow_editor_state.dart';

/// The editor holds flow [id] with nothing on the canvas: what it held of
/// another flow goes (its draft, history, live values), so nothing of that
/// flow is drawn or deployed under [id]. What belongs to the editor itself
/// stays (palette tab, clipboard, tree query, the library).
class UnloadFlowAction extends Action {
  UnloadFlowAction(this.id);

  final String id;

  @override
  AppState reduce() {
    final held = flowEditor;
    return state.copyWith(
      flowEditor: FlowEditorState(
        flowId: id,
        types: held.types,
        palette: held.palette,
        clipboard: held.clipboard,
        treeQuery: held.treeQuery,
        library: held.library,
        libraryOff: held.libraryOff,
      ),
    );
  }
}
