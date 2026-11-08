import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Stages [staged]: a change on the same key and field replaces the staged
/// one (its `from` stays the value before the first edit).
class AddChangesAction extends Action {
  AddChangesAction(this.staged);

  final IList<StagedChange> staged;

  @override
  AppState reduce() {
    var table = state.changes.table;
    var view = state.changes.view;
    for (final c in staged) {
      final same = table.values
          .where((o) => o.key == c.key && o.field == c.field)
          .firstOrNull;
      if (same != null) {
        table = table.add(same.id, c.copyWith(id: same.id, from: same.from));
      } else {
        table = table.add(c.id, c);
        view = view.add(c.id);
      }
    }
    return state.copyWith.changes(table: table, view: view, message: null);
  }
}
