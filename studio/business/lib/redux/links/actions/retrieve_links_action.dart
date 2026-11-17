import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/broker_text.dart';
import '../../../wyrm/decode/link_info.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/links` of the site: the ids, then each link's full meta (the
/// admin's `view=list` carries no `attr`). Link states are live values of
/// `sys/links/*/state`, watched by the Links screen. The attribute
/// `updates_available` of `sys/links` itself counts the links whose package
/// has a newer version (ADR 0048 §1).
///
/// A site switch starts it without waiting for it, while a read of the
/// site left may still run, and several screens read the same site: the
/// newest request never waits for an older one. An answer is kept only for
/// the site still viewed, and only while no read started after it has been
/// kept already (`deps.latest`), so the table never goes back to an older
/// read; whoever awaits a read finds a table at least as new as its own.
/// A failure of a read that was replaced (the site was left, or a newer
/// read is under way) is not said: the newer read says its own.
class RetrieveLinksAction extends Action with WaitingAction {
  RetrieveLinksAction({super.quiet});

  @override
  Action again() => RetrieveLinksAction(quiet: quiet);

  /// The site this read asked and its place among the reads of the links;
  /// null before it asked.
  ({String root, int token})? _asked;

  @override
  Object? wrapError(Object error, StackTrace stackTrace) => switch (_asked) {
    (:final root, :final token)
        when site.root != root ||
            deps.latest.newerStarted(RetrieveLinksAction, token) =>
      null,
    _ => super.wrapError(error, stackTrace),
  };

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final latest = deps.latest;
    final token = latest.start(RetrieveLinksAction);
    _asked = (root: root, token: token);
    final api = deps.wyrm;
    final base = '$root/sys/links';
    final ids = await listOf(api, base);
    final links = await Future.wait([
      for (final c in ids)
        metaOf(api, '$base/${c.name}').then(
          // an attribute this client cannot read is left at its default
          // and logged with its field; the link keeps the rest
          (m) => linkInfoOf(c.name, m, where: '$base/${c.name}'),
        ),
    ]);
    final version = await readValue(api, '$root/sys/version');
    // A broker before ADR 0048, or a reader without the meta: no count.
    var updatesAvailable = 0;
    try {
      updatesAvailable =
          updatesAvailableOf(await api.meta(base)).orWarn(base) ?? 0;
    } on WyrmException {
      updatesAvailable = 0;
    }
    // Every `await` is behind: the site may have been left, and a read
    // started later may have answered first.
    if (site.root != root || latest.newerKept(RetrieveLinksAction, token)) {
      return null;
    }
    latest.keep(RetrieveLinksAction, token);
    return state.copyWith.links(
      version: brokerTextOf(version, 'sys', 'version').orWarn(root),
      table: IMap<String, LinkInfo>.fromValues(
        values: links,
        keyMapper: (l) => l.id,
      ),
      view: [for (final l in links) l.id].lock,
      updatesAvailable: updatesAvailable,
    );
  }
}
