import 'package:models/install_field.dart';
import 'package:models/install_source.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The package brought to Add a link. What the broker said of the URL or
/// the ref it refused is said no longer once the source changes, and the
/// rights accepted for the package before are accepted no longer: consent
/// is given to one package, not to whatever comes next.
class SetSourceAction extends Action {
  SetSourceAction(this.source);

  final InstallSource? source;

  @override
  AppState reduce() => switch (linkInstall.refusedField) {
    null || InstallField.name => state.copyWith.linkInstall(
      source: source,
      acceptRights: false,
    ),
    InstallField.url ||
    InstallField.git ||
    InstallField.ref => state.copyWith.linkInstall(
      source: source,
      acceptRights: false,
      refusedField: null,
      refusedSaid: null,
    ),
  };
}
