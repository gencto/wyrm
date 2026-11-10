import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/invoke_node_action.dart';

/// `sys/tokens` ▸ `add {count, hours}` (config): tokens that admit a broker
/// below at once. They are shown once: the answer is kept in
/// `nodes.results` under this action, never persisted.
class IssueSiteTokenAction extends Action with WaitingAction {
  IssueSiteTokenAction({this.count = 1, this.hours = 24});

  @override
  Action again() => IssueSiteTokenAction(count: count, hours: hours);

  final int count;
  final int hours;

  @override
  Future<AppState> reduce() async {
    final key = '${site.root}/sys/tokens';
    final rows = await invokeAll(
      deps.wyrm,
      key,
      'add',
      valueOf({'count': count, 'hours': hours}),
    );
    return state.copyWith.nodes(
      results: state.nodes.results.add(
        InvokeNodeAction.resultId(key, 'add'),
        [for (final r in rows) text(r) ?? '${toDart(r)}'].lock,
      ),
    );
  }
}
