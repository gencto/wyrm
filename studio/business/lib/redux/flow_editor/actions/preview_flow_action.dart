import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Runs the draft as a preview (`dataflows` ▸ `preview`, debounced by the
/// service) while it differs from the deployed version, so its blocks show
/// live values before a deploy. A draft equal to the deployed version (its
/// layout aside), or [stop], ends the preview and drops its values: the
/// watch shows the deployed flow's.
class PreviewFlowAction extends Action {
  PreviewFlowAction({this.stop = false});

  /// The editor closes.
  final bool stop;

  @override
  AppState? reduce() {
    final root = site.root;
    // The flow itself, also while the canvas shows the inside of a block.
    final d = flowEditor.root;
    final dep = flowEditor.deployed;
    final def = stop || d == null || root == null ? null : previewDefOf(d);
    final run = def != null && dep != null && previewDefOf(dep) == def
        ? null
        : def;
    deps.flowPreview.show(run == null ? null : '$root/dataflows', run);
    final ed = flowEditor;
    if (run != null ||
        (ed.previewPorts.isEmpty &&
            ed.previewSinks.isEmpty &&
            ed.previewError == null)) {
      return null;
    }
    return state.copyWith.flowEditor(
      previewPorts: ed.previewPorts.clear(),
      previewSinks: ed.previewSinks.clear(),
      previewError: null,
    );
  }
}
