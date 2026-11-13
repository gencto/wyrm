import '../../app_state.dart';
import '../../common/action.dart';

/// One batch of data-model writes from `ViewBridgeService`: path → value.
/// A null value removes the path and everything below it.
class SetViewDataAction extends Action {
  SetViewDataAction(this.changed);

  final Map<String, Object?> changed;

  @override
  AppState? reduce() {
    if (!views.open) {
      return null;
    }
    var data = views.data;
    for (final MapEntry(key: path, :value) in changed.entries) {
      if (value != null) {
        data = data.add(path, value);
      } else {
        final below = '$path/';
        data = data.removeWhere((k, _) => k == path || k.startsWith(below));
      }
    }
    return data == views.data ? null : state.copyWith.views(data: data);
  }
}
