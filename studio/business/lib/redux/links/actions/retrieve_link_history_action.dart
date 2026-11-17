import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/sys_answers.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `history` (config): the revisions of the link's
/// parameters, newest first, into `links.revisions`.
class RetrieveLinkHistoryAction extends Action with WaitingAction {
  RetrieveLinkHistoryAction(this.id);

  @override
  Action again() => RetrieveLinkHistoryAction(id);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;

  @override
  Future<AppState> reduce() async {
    final rows = await askAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'history',
    );
    final revs = linkRevisionsOf(rows).orRefuse(
      key: '${site.root}/sys/links/$id',
      call: 'history',
      thing: id,
    );
    return state.copyWith.links(revisions: revs.lock);
  }
}
