import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/quarantine_entry.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Puts [QuarantineEntry]s into the `quarantine` table, keyed by `cn`.
///
/// With [replace] the table and its view become exactly these items, in this
/// order (a fresh read of the whole list); without it the items are merged in
/// and a new id is appended to the view.
class AddQuarantineAction extends Action {
  AddQuarantineAction(this._items, {this.replace = false});

  final IList<QuarantineEntry> _items;
  final bool replace;

  @override
  AppState reduce() {
    final byId = IMap<String, QuarantineEntry>.fromValues(
      values: _items,
      keyMapper: (item) => item.cn,
    );
    if (replace) {
      return state.copyWith.quarantine(
        table: byId,
        view: [for (final item in _items) item.cn].lock,
      );
    }
    final table = state.quarantine.table;
    final view = state.quarantine.view;
    return state.copyWith.quarantine(
      table: table.addAll(byId),
      view: view.addAll([
        for (final item in _items)
          if (!table.containsKey(item.cn)) item.cn,
      ]),
    );
  }
}
