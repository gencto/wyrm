import '../../../wyrm/discovery.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// One service the browse found, or one address of a range probe: its
/// `/api/info` makes its row, merged by site into `discovery.found`
/// (`mergeFound`). An answer for an older search is dropped.
class CheckFoundGatewayAction extends Action {
  CheckFoundGatewayAction(this.found, this.scan);

  final Announcement found;

  /// The search it answers (`discovery.scan`).
  final int scan;

  @override
  Future<AppState?> reduce() async {
    if (scan != discovery.scan) {
      return null;
    }
    final row = await checkFound(
      found,
      reader: deps.gatewayInfo,
      trust: GatewayTrust(discovery.pins),
      now: DateTime.now().millisecondsSinceEpoch,
    );
    if (row == null || scan != discovery.scan || !discovery.open) {
      return null;
    }
    return state.copyWith.discovery(found: mergeFound(discovery.found, row));
  }
}
