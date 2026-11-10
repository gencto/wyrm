import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/profile_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The device profiles the admin publishes: the names under `pub` and the
/// point count of each `pub/<name>/~meta`.
///
/// A broker that does not list `pub` (wyrmd 0.1.0 answers `not_found`: its
/// profiles are read one by one by name) leaves the list empty and its
/// answer in `system.profilesNote`, which the screen shows instead of rows.
class RetrieveProfilesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final List<Child> names;
    try {
      names = await api.children('$root/pub');
    } on WyrmException catch (e) {
      return state.copyWith.system(
        profiles: const IListConst([]),
        profilesNote: '${e.status.name}: ${e.message}'.trim(),
      );
    }
    final profiles = await Future.wait([
      for (final c in names)
        api
            .meta('$root/pub/${c.name}')
            .then<ProfileInfo>(
              (m) => ProfileInfo(
                name: c.name,
                points: m.children?.length ?? m.childrenCount ?? 0,
              ),
              onError: (Object _) => ProfileInfo(name: c.name),
            ),
    ]);
    return state.copyWith.system(profiles: profiles.lock, profilesNote: null);
  }
}
