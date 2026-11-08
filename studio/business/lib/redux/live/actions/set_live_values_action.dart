import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// One batch from `LiveValuesService`: the changed keys only; a null value
/// removes the key.
class SetLiveValuesAction extends Action {
  SetLiveValuesAction(this.changed);

  final Map<String, LiveValue?> changed;

  @override
  AppState? reduce() {
    if (changed.isEmpty) {
      return null;
    }
    var values = state.live.values;
    for (final MapEntry(:key, :value) in changed.entries) {
      values = value == null ? values.remove(key) : values.add(key, value);
    }
    return state.copyWith.live(values: values);
  }
}
