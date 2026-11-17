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
      now: deps.clock().millisecondsSinceEpoch,
    );
    if (row == null || scan != discovery.scan || !discovery.open) {
      return null;
    }
    // Its row says how long ago it was seen against `clock.now`, stamped
    // with the row: a new row is `seen now`, never against an older clock.
    return state.copyWith(
      clock: state.clock.copyWith(now: deps.clock()),
      discovery: state.discovery.copyWith(
        found: mergeFound(discovery.found, row),
      ),
    );
  }
}
