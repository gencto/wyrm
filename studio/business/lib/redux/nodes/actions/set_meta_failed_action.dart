import '../../app_state.dart';
import '../../common/action.dart';

/// Reading the `~meta` of [key] failed with [reason] (the status' wire
/// name): its tree row and the inspector show `read failed`
/// (docs/design/specs/errors.md §4) until a read of it answers. A null
/// [reason] takes the mark away.
class SetMetaFailedAction extends Action {
  SetMetaFailedAction(this.key, this.reason);

  final String key;
  final String? reason;

  @override
  AppState? reduce() {
    final now = nodes.metaFailed;
    if (now[key] == reason) {
      return null;
    }
    return state.copyWith.nodes(
      metaFailed: switch (reason) {
        final r? => now.add(key, r),
        null => now.remove(key),
      },
    );
  }
}
