import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_info.dart';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/link_info_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/links` of the site: the ids, then each link's full meta (the
/// admin's `view=list` carries no `attr`). Link states are live values of
/// `sys/links/*/state`, watched by the Links screen. The attribute
/// `updates_available` of `sys/links` itself counts the links whose package
/// has a newer version (ADR 0048 §1).
class RetrieveLinksAction extends Action with WaitingAction {
  RetrieveLinksAction({super.quiet});

  @override
  Action again() => RetrieveLinksAction(quiet: quiet);

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/links';
    final ids = await listOf(api, base);
    final links = await Future.wait([
      for (final c in ids)
        metaOf(api, '$base/${c.name}').then((m) => linkInfoOf(c.name, m)),
    ]);
    final version = await readValue(api, '$root/sys/version');
    // A broker before ADR 0048, or a reader without the meta: no count.
    var updatesAvailable = 0;
    try {
      updatesAvailable =
          integer(attrOf(await api.meta(base), 'updates_available')) ?? 0;
    } on WyrmException {
      updatesAvailable = 0;
    }
    return state.copyWith.links(
      version: switch (version) {
        VStr(:final v) => v,
        _ => null,
      },
      table: IMap<String, LinkInfo>.fromValues(
        values: links,
        keyMapper: (l) => l.id,
      ),
      view: [for (final l in links) l.id].lock,
      updatesAvailable: updatesAvailable,
    );
  }
}
