import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/system_notice.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/cleared_links.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../problems/actions/show_notice_action.dart';

/// `sys` ▸ `clear_conns` (config): the broker forgets the runtime external
/// links that are not connected and answers their ids ([removed]; nothing
/// when there were none). Their ids are retired. The links are read again,
/// and a toast says which went (System › Maintenance asks first).
class ClearConnsAction extends Action with NonReentrant, WaitingAction {
  @override
  Action again() => ClearConnsAction();

  /// The ids the broker removed, known when the action has ended.
  List<String> removed = const [];

  @override
  Future<AppState?> reduce() async {
    final rows = await invokeAll(deps.wyrm, '${site.root}/sys', 'clear_conns');
    final cleared = clearedLinksOf(
      rows,
    ).orWarn('clear_conns of ${site.viewed}');
    removed = cleared ?? const [];
    await dispatchAndWait(RetrieveLinksAction(quiet: true));
    // an answer this client cannot read says nothing (it is logged), not
    // "none removed"
    if (cleared != null) {
      await dispatchAndWait(
        ShowNoticeAction.system(SystemNotice.cleared(cleared.lock)),
      );
    }
    return null;
  }
}
