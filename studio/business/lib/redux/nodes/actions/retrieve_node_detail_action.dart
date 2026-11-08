import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the full `~meta` of [key] into `nodes.detail` (the actions, `cfg`
/// and `attr` the tree's `view=list` leaves out).
class RetrieveNodeDetailAction extends Action with WaitingAction {
  RetrieveNodeDetailAction(this.key);

  final String key;

  @override
  Future<AppState> reduce() async {
    final m = await call('Cannot read $key', () => deps.wyrm.meta(key));
    return state.copyWith.nodes(
      detail: state.nodes.detail.add(key, nodeDetailOf(key, m)),
    );
  }
}
