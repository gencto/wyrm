import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/latest.dart';
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
/// newest request never waits for an older one. Each site has its own
/// order (`deps.latest`, keyed by the site's root), so a read of another
/// site says nothing of this one's.
/// - An answer is kept only for the site still viewed, and only while no
///   read of that site started after it has been kept already: the table
///   never goes back to an older read, and an older good answer still
///   stands when the newer read failed.
/// - A read that failed while a newer read of the same site is under way
///   has nothing fresh for whoever awaits it: it ends as that newer read
///   ends (well, or with its failure, said once by the newer read).
/// - A failure for a site that was left is not said.
class RetrieveLinksAction extends Action with WaitingAction {
  RetrieveLinksAction({super.quiet});

  @override
  Action again() => RetrieveLinksAction(quiet: quiet);

  /// The site this read asked; null before it asked.
  String? _root;

  /// This read failed and ended as the newer read of its site did: that
  /// read says the failure, this one opens no second dialog for it.
  var _echoes = false;

  @override
  Object? wrapError(Object error, StackTrace stackTrace) {
    if (_root != null && site.root != _root) {
      return null;
    }
    final wrapped = super.wrapError(error, stackTrace);
    return _echoes && wrapped is UserException
        ? wrapped.withDialog(false)
        : wrapped;
  }

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    _root = root;
    final run = deps.latest.start(LatestKey(LatestRead.links, root));
    try {
      final read = await _read(root);
      // Every `await` is behind: the site may have been left, and a read
      // of it started later may have answered first.
      if (site.root != root || run.outdated) {
        run.end();
        return null;
      }
      run
        ..keep()
        ..end();
      return state.copyWith.links(
        version: read.version,
        table: IMap<String, LinkInfo>.fromValues(
          values: read.links,
          keyMapper: (l) => l.id,
        ),
        view: [for (final l in read.links) l.id].lock,
        updatesAvailable: read.updatesAvailable,
      );
    } on Object catch (e, stack) {
      final newer = site.root == root ? deps.latest.newer(run) : null;
      if (newer == null) {
        run.end(e, stack);
        rethrow;
      }
      // Nothing fresh came of this read; a newer one is under way, and
      // whoever awaits this one gets that one's outcome.
      _echoes = true;
      try {
        await newer;
      } on Object catch (e, stack) {
        run.end(e, stack);
        rethrow;
      }
      run.end();
      return null;
    }
  }

  /// Reads the links of [root].
  Future<_LinksRead> _read(String root) async {
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
    return _LinksRead(
      version: brokerTextOf(version, 'sys', 'version').orWarn(root),
      links: links,
      updatesAvailable: updatesAvailable,
    );
  }
}

/// What one read of a site's links found.
final class _LinksRead {
  const _LinksRead({
    required this.version,
    required this.links,
    required this.updatesAvailable,
  });

  final String? version;
  final List<LinkInfo> links;
  final int updatesAvailable;
}
