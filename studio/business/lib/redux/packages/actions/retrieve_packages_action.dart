import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/package_info.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/package_info_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/packages` of the site, each by its full meta.
class RetrievePackagesAction extends Action with WaitingAction {
  @override
  Action again() => RetrievePackagesAction();

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/packages';
    final names = await listOf(api, base);
    final list = await Future.wait([
      for (final c in names)
        metaOf(api, '$base/${c.name}').then((m) => packageInfoOf(c.name, m)),
    ]);
    return state.copyWith.packages(
      table: IMap<String, PackageInfo>.fromValues(
        values: list,
        keyMapper: (p) => p.name,
      ),
      view: [for (final p in list) p.name].lock,
    );
  }
}
