import '../../app_state.dart';
import '../../common/action.dart';

/// Listing the children of [key] failed with [reason] (the status' wire
/// name): its tree row and the inspector show `read failed`
/// (docs/design/specs/errors.md §4) until the list answers. A null
/// [reason] takes the mark away.
class SetListFailedAction extends Action {
  SetListFailedAction(this.key, this.reason);

  final String key;
  final String? reason;

  @override
  AppState? reduce() {
    final now = nodes.listFailed;
    if (now[key] == reason) {
      return null;
    }
    return state.copyWith.nodes(
      listFailed: switch (reason) {
        final r? => now.add(key, r),
        null => now.remove(key),
      },
    );
  }
}
