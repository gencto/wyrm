import '../../app_state.dart';
import '../../common/action.dart';

/// Follows the live values of deployed flow [id] (`dataflows/<id>` ▸
/// `watch`, ADR 0038 §3) while the editor shows it; null stops and drops
/// them. A new flow has nothing deployed to watch.
class WatchFlowAction extends Action {
  WatchFlowAction(this.id);

  final String? id;

  @override
  AppState? reduce() {
    final root = site.root;
    final id = this.id;
    deps.flowWatch.follow(
      root == null || id == null || id.isEmpty ? null : '$root/dataflows/$id',
    );
    return flowEditor.ports.isEmpty && flowEditor.watchRefused == null
        ? null
        : state.copyWith.flowEditor(
            ports: flowEditor.ports.clear(),
            watchRefused: null,
          );
  }
}
