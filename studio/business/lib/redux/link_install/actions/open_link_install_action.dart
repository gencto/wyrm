import 'package:models/install_path.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'choose_install_source_action.dart';
import 'retrieve_install_catalog_action.dart';

/// Add a link is opened, one intent: it starts on the official list with
/// no answer (shown at once), then reads what the site offers (shown when
/// it comes, with the read's own wait). It changes no state itself.
class OpenLinkInstallAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(ChooseInstallSourceAction(InstallPath.official));
    await dispatchAndWait(RetrieveInstallCatalogAction());
    return null;
  }
}
