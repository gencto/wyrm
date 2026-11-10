import '../../app_state.dart';
import '../../common/action.dart';

/// Reading the value of [key] failed with [reason] (its wire name): the row
/// shows `read failed` and no value (docs/design/specs/errors.md §4) until
/// a value comes.
class SetReadFailedAction extends Action {
  SetReadFailedAction(this.key, this.reason);

  final String key;
  final String reason;

  @override
  AppState? reduce() => live.failed[key] == reason
      ? null
      : state.copyWith.live(failed: live.failed.add(key, reason));
}
