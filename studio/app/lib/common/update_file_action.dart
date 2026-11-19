import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/updates/actions/update_package_action.dart';

import 'files.dart';

/// *Choose the archive…* of a custom package's update: a zip is picked and
/// its package updated from it, one intent (studio-rules §1, §9). In
/// `app`: the file picker is the app's. Nothing when the user leaves the
/// dialog.
class UpdateFromFileAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final f = await pickFile(extensions: const ['zip']);
    if (f == null) {
      return null;
    }
    try {
      final zip = await f.read(0, f.size);
      await dispatchAndWait(UpdatePackageAction(zip: zip));
    } finally {
      await f.close();
    }
    return null;
  }
}
