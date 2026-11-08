import '../../app_state.dart';
import '../../common/action.dart';

/// Drops one staged change.
class RemoveChangeAction extends Action {
  RemoveChangeAction(this.id);

  final String id;

  @override
  AppState reduce() => state.copyWith.changes(
    table: changes.table.remove(id),
    view: changes.view.remove(id),
    open: changes.view.length > 1 && changes.open,
  );
}
