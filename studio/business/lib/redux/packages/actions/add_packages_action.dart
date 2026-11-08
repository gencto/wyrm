import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/package_info.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Puts [PackageInfo]s into the `packages` table, keyed by `name`.
///
/// With [replace] the table and its view become exactly these items, in this
/// order (a fresh read of the whole list); without it the items are merged in
/// and a new id is appended to the view.
class AddPackagesAction extends Action {
  AddPackagesAction(this._items, {this.replace = false});

  final IList<PackageInfo> _items;
  final bool replace;

  @override
  AppState reduce() {
    final byId = IMap<String, PackageInfo>.fromValues(
      values: _items,
      keyMapper: (item) => item.name,
    );
    if (replace) {
      return state.copyWith.packages(
        table: byId,
        view: [for (final item in _items) item.name].lock,
      );
    }
    final table = state.packages.table;
    final view = state.packages.view;
    return state.copyWith.packages(
      table: table.addAll(byId),
      view: view.addAll([
        for (final item in _items)
          if (!table.containsKey(item.name)) item.name,
      ]),
    );
  }
}
