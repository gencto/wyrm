import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/install_target.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/catalog.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads what Add a link offers on the site on screen: the drivers the
/// broker hosts (`sys/links` ▸ `install` `driver` choices) and the packages
/// its repository has for its host (`install_repo` `package` choices); the
/// brokers a link can go to (this one and the sites below it, each refused
/// with the reason when the user has no config on its `sys/links`).
class RetrieveInstallCatalogAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    final viewed = site.viewed;
    if (root == null || viewed == null) {
      return null;
    }
    final api = deps.wyrm;
    final meta = await call(
      'Cannot read sys/links',
      () => api.meta('$root/sys/links'),
    );
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
    );
    final sites = [
      viewed,
      for (final c in site.choices)
        if (c.relation == 'downstream' && c.site != viewed) c.site,
    ];
    final targets = await Future.wait([
      for (final s in sites)
        readValue(api, 'wy/$s/sys/distribution').then(
          (d) => InstallTarget(
            site: s,
            role: s == viewed ? 'this broker' : 'downstream',
            // `os-arch` when the broker says it; `sys/distribution` of
            // these brokers names the build (`rust (prod)`), not the host.
            host: switch (d) {
              VStr(:final v)
                  when RegExp('^(linux|macos|windows)-').hasMatch(v) =>
                v,
              _ => null,
            },
            refused: site.needs('config', 'wy/$s/sys/links'),
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
