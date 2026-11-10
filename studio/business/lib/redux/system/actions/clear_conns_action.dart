import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';

/// `sys` ▸ `clear_conns` (config): the broker forgets the runtime external
/// links that are not connected and answers their ids ([removed]; nothing
/// when there were none). Their ids are retired. The links are read again.
class ClearConnsAction extends Action with NonReentrant, WaitingAction {
  /// The ids the broker removed, known when the action has ended.
  List<String> removed = const [];

  @override
  Future<AppState?> reduce() async {
    final rows = await invokeAll(deps.wyrm, '${site.root}/sys', 'clear_conns');
    removed = [
      for (final r in rows)
        ...switch (r) {
          VArray() => strings(r),
          VStr(:final v) => [v],
          _ => const <String>[],
        },
    ];
    await dispatchAndWait(RetrieveLinksAction(quiet: true));
    return null;
  }
}
