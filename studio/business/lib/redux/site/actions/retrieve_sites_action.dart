import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_relation.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/peers.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';

/// Fills the site switcher: the site logged into, every broker below it
/// (`downstream/<d>` of kind `wy:broker`, and theirs, at most [depth] hops)
/// and the brokers above it (`sys/upstream/<u>`). A site the user may not
/// list is left out, not reported.
class RetrieveSitesAction extends Action with WaitingAction {
  RetrieveSitesAction({this.depth = 4, super.quiet});

  @override
  Action again() => RetrieveSitesAction(depth: depth, quiet: quiet);

  final int depth;

  @override
  Future<AppState?> reduce() async {
    final home = site.name;
    if (home == null) {
      return null;
    }
    final api = deps.wyrm;
    final choices = <SiteChoice>[SiteChoice(site: home)];
    final seen = {home};
    final unread = Unread();
    var frontier = [_Hop(home, null)];
    for (var hop = 0; hop < depth && frontier.isNotEmpty; hop++) {
      final next = <_Hop>[];
      for (final _Hop(site: s, :via) in frontier) {
        final List<Child> below;
        try {
          below = await api.children('wy/$s/downstream');
        } on WyrmException {
          continue;
        }
        for (final c in below) {
          // a broker node this client cannot read is no site to choose;
          // the user is told of it
          final d = switch (brokerSiteOf(c)) {
            final read? => unread.take(
              read,
              name: '$s/downstream/${c.name}',
              where: 'wy/$s/downstream/${c.name}',
            ),
            null => null,
          };
          if (d != null && seen.add(d)) {
            choices.add(
              SiteChoice(
                site: d,
                relation: SiteRelation.downstream,
                via: via ?? s,
              ),
            );
            next.add(_Hop(d, s == home ? null : s));
          }
        }
      }
      frontier = next;
    }
    try {
      for (final u in await api.children('wy/$home/sys/upstream')) {
        if (seen.add(u.name)) {
          choices.add(
            SiteChoice(site: u.name, relation: SiteRelation.upstream),
          );
        }
      }
    } on WyrmException {
      // No rights on sys: no upstream entries.
    }
    if (unread.problem(key: 'wy/$home/downstream', call: const .known(.list))
        case final p?) {
      dispatchSync(AddProblemAction(p));
    }
    return state.copyWith.site(choices: choices.lock);
  }
}

/// A site to list the brokers below, and the site it is relayed through
/// (null: reached directly from the home site).
final class _Hop {
  const _Hop(this.site, this.via);

  final String site;
  final String? via;
}
