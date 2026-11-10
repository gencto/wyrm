import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The `description` attribute and the unit of every value node of `sys`
/// (a tile's tooltip and unit). The admin's `view=list` carries no `attr`,
/// so each node's `~meta` is read on its own, once per site: a site whose
/// descriptions are held is not read again.
class RetrieveSysAboutAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || system.about.keys.any((k) => k.startsWith('$root/'))) {
      return null;
    }
    final api = deps.wyrm;
    final List<Child> nodes;
    try {
      nodes = await api.children('$root/sys');
    } on WyrmException {
      return null;
    }
    final about = <String, String>{};
    final units = <String, String>{};
    await Future.wait([
      for (final c in nodes)
        if (c.meta.ty != null)
          api.meta('$root/sys/${c.name}').then<void>(
            (m) {
              if (str(m.attr?['description']) case final d?) {
                about['$root/sys/${c.name}'] = d;
              }
              if (m.unit case final u?) {
                units['$root/sys/${c.name}'] = '$u';
              }
            },
            onError: (Object _) {},
          ),
    ]);
    return state.copyWith.system(about: about.lock, units: units.lock);
  }
}
