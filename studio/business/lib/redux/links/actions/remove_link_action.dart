import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `remove` (config): stops it and deletes its tree; a
/// process or external link's id is retired.
class RemoveLinkAction extends Action with NonReentrant, WaitingAction {
  RemoveLinkAction(this.id);

  @override
  Action again() => RemoveLinkAction(id);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;

  @override
  Future<AppState> reduce() async {
    await invokeAll(deps.wyrm, '${site.root}/sys/links/$id', 'remove');
    return state.copyWith.links(
      table: links.table.remove(id),
      view: links.view.remove(id),
      selectedLink: links.selectedLink == id ? null : links.selectedLink,
    );
  }
}
