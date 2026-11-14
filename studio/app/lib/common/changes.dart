import 'package:business/redux/app_state.dart';
import 'package:localization/localization.dart';
import 'package:ui/overlays/review_panel.dart';

/// The staged changes as review cards, with the level each needs checked
/// against the user's own grants.
List<ChangeCardVm> changeCards(Selectors s) => [
  for (final id in s.changes.view)
    if (s.changes.table[id] case final c?)
      ChangeCardVm(
        id: c.id,
        op: c.op,
        // a link's params: the whole key, so the site is never hidden
        key_: c.key.contains('/sys/links/') ? c.key : shortKey(c.key),
        field: c.field,
        from: c.from,
        to: c.to,
        allowed: s.site.can(c.level, c.key),
        levelText: s.site.can(c.level, c.key)
            ? S.current.needsLevelYouHaveIt(c.level)
            : S.current.needsLevelYouHave(c.level, s.site.levelOn(c.key)),
      ),
];

/// `…/plc1/t2`: the last two segments of a key.
String shortKey(String key) {
  final parts = key.split('/');
  return parts.length <= 3
      ? key
      : '…/${parts.sublist(parts.length - 2).join('/')}';
}
