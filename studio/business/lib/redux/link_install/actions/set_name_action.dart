import '../../app_state.dart';
import '../../common/action.dart';

/// The link's name in Add a link. What the broker said of the name it
/// refused is said no longer once the name changes.
class SetNameAction extends Action {
  SetNameAction(this.name);

  final String? name;

  @override
  AppState reduce() => linkInstall.refusedField == 'name'
      ? state.copyWith.linkInstall(
          name: name,
          refusedField: null,
          refusedSaid: null,
        )
      : state.copyWith.linkInstall(name: name);
}
