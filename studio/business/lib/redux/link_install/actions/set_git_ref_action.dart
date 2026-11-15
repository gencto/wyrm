import 'package:models/install_source.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'set_source_action.dart';

/// The Git ref of a custom package as it is typed (null: none); nothing
/// before the repository's URL is.
class SetGitRefAction extends Action {
  SetGitRefAction(this.ref);

  final String? ref;

  @override
  AppState? reduce() {
    final url = switch (linkInstall.source) {
      InstallSourceGit(:final url) || InstallSourceUrl(:final url) => url,
      _ => null,
    };
    if (url == null) {
      return null;
    }
    dispatchSync(SetSourceAction(InstallSource.git(url: url, ref: ref)));
    return null;
  }
}
