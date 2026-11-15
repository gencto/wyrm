import 'package:models/install_source.dart';
import 'package:models/package_method.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'set_source_action.dart';

/// The URL of a custom package as it is typed: a package zip at a URL, or
/// a Git repository (its ref kept) when the method is Git; null clears it.
class SetPackageUrlAction extends Action {
  SetPackageUrlAction(this.url);

  final String? url;

  @override
  AppState? reduce() {
    final u = url;
    final ref = switch (linkInstall.source) {
      InstallSourceGit(:final ref) => ref,
      _ => null,
    };
    dispatchSync(
      SetSourceAction(switch (linkInstall.method) {
        _ when u == null => null,
        PackageMethod.git => InstallSource.git(url: u, ref: ref),
        PackageMethod.url ||
        PackageMethod.zip ||
        PackageMethod.wasm => InstallSource.url(url: u),
      }),
    );
    return null;
  }
}
