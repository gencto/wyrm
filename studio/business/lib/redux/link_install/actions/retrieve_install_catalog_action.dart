import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/install_target.dart';
import 'package:models/site_relation.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/catalog.dart';
import '../../../wyrm/decode/broker_text.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads what Add a link offers on the site on screen: the drivers the
/// broker hosts (`sys/links` ▸ `install` `driver` choices) and the packages
/// its repository has for its host (`install_repo` `package` choices),
/// described by the rows of `attr.catalog` where the broker has them; the
/// brokers a link can go to (this one and the sites below it; which ones
/// the user may install on is `installTargetReason`, read from the grants
/// when drawn).
class RetrieveInstallCatalogAction extends Action with WaitingAction {
  @override
  Action again() => RetrieveInstallCatalogAction();

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    final viewed = site.viewed;
    if (root == null || viewed == null) {
      return null;
    }
    final api = deps.wyrm;
    final (meta, version) = await (
      metaOf(api, '$root/sys/links'),
      readValue(api, '$root/sys/version'),
    ).wait;
    List<String> choices(String action, String param) =>
        meta.actions?[action]?.params[param]?.enumValues ?? const [];
    final counts = <String, int>{};
    for (final l in links.table.values) {
      counts[l.driver] = (counts[l.driver] ?? 0) + 1;
    }
    final catalog = catalogOf(
      drivers: choices('install', 'driver'),
      packages: choices('install_repo', 'package'),
      existing: counts,
      brokerVersion: brokerTextOf(
        version,
        'sys',
        'version',
      ).orWarn('sys/version of $viewed'),
      // ADR 0043 §7: titles, versions and the official mark from the
      // broker; an older broker sends none.
      rows: catalogRowsOf(meta.attr),
    );
    final sites = [
      viewed,
      for (final c in site.choices)
        if (c.relation == SiteRelation.downstream && c.site != viewed) c.site,
    ];
    final targets = await Future.wait([
      for (final s in sites)
        readValue(api, 'wy/$s/sys/distribution').then(
          (d) => InstallTarget(
            site: s,
            host: hostOf(
              brokerTextOf(
                d,
                'sys',
                'distribution',
              ).orWarn('sys/distribution of $s'),
            ),
          ),
        ),
    ]);
    return state.copyWith.linkInstall(
      catalog: catalog,
      targets: targets.lock,
      broker: linkInstall.broker ?? viewed,
    );
  }
}
