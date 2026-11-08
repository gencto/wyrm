import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_info.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/link_info_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/links` of the site: the ids, then each link's full meta (the
/// admin's `view=list` carries no `attr`). Link states are live values of
/// `sys/links/*/state`, watched by the Links screen.
class RetrieveLinksAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/links';
    final ids = await call(
      'Cannot list the links',
      () => api.children(base),
    );
    final links = await Future.wait([
      for (final c in ids)
        call(
          'Cannot read link ${c.name}',
          () => api.meta('$base/${c.name}'),
        ).then((m) => linkInfoOf(c.name, m)),
    ]);
    return state.copyWith.links(
      table: IMap<String, LinkInfo>.fromValues(
        values: links,
        keyMapper: (l) => l.id,
      ),
      view: [for (final l in links) l.id].lock,
    );
  }
}
