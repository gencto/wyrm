import 'package:models/install_path.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/link_install_state.dart';

/// Starts Add a link over on [path]: the step, the choice and every answer
/// are cleared; the catalog and the brokers stay.
class ChooseInstallSourceAction extends Action {
  ChooseInstallSourceAction(this.path);

  final InstallPath path;

  @override
  AppState reduce() => state.copyWith(
    linkInstall: LinkInstallState(
      path: path,
      catalog: linkInstall.catalog,
      targets: linkInstall.targets,
      broker: site.viewed,
    ),
  );
}
