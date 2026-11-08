import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/site_choice.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Fills the site switcher: the site logged into, every broker below it
/// (`downstream/<d>` of kind `wy:broker`, and theirs, at most [depth] hops)
/// and the brokers above it (`sys/upstream/<u>`). A site the user may not
/// list is left out, not reported.
class RetrieveSitesAction extends Action with WaitingAction {
  RetrieveSitesAction({this.depth = 4});

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
    var frontier = [(home, null as String?)];
    for (var hop = 0; hop < depth && frontier.isNotEmpty; hop++) {
      final next = <(String, String?)>[];
      for (final (s, via) in frontier) {
        final List<Child> below;
        try {
          below = await api.children('wy/$s/downstream');
        } on WyrmException {
          continue;
        }
        for (final c in below) {
          if (c.meta.profileName != 'wy:broker') {
            continue;
          }
          final d = str(attrOf(c.meta, 'site')) ?? c.name;
          if (seen.add(d)) {
            choices.add(
              SiteChoice(site: d, relation: 'downstream', via: via ?? s),
            );
            next.add((d, s == home ? null : s));
          }
        }
      }
      frontier = next;
    }
    try {
      for (final u in await api.children('wy/$home/sys/upstream')) {
        if (seen.add(u.name)) {
          choices.add(SiteChoice(site: u.name, relation: 'upstream'));
        }
      }
    } on WyrmException {
      // No rights on sys: no upstream entries.
    }
    return state.copyWith.site(choices: choices.lock);
  }
}
