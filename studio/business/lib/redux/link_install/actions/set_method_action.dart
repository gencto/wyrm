import 'package:models/install_field.dart';
import 'package:models/package_method.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// How the custom package is brought: what was brought another way is
/// dropped, and with it what the broker said of a URL or a ref and the
/// rights accepted for it.
class SetMethodAction extends Action {
  SetMethodAction(this.method);

  final PackageMethod method;

  @override
  AppState? reduce() {
    final keepRefusal =
        linkInstall.refusedField == null ||
        linkInstall.refusedField == InstallField.name;
    if (method == linkInstall.method &&
        linkInstall.source == null &&
        !linkInstall.acceptRights &&
        keepRefusal) {
      return null;
    }
    return state.copyWith.linkInstall(
      method: method,
      source: null,
      acceptRights: false,
      refusedField: keepRefusal ? linkInstall.refusedField : null,
      refusedSaid: keepRefusal ? linkInstall.refusedSaid : null,
    );
  }
}
