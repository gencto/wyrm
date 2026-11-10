import 'package:models/install_source.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The package brought to Add a link. What the broker said of the URL or
/// the ref it refused is said no longer once the source changes.
class SetSourceAction extends Action {
  SetSourceAction(this.source);

  final InstallSource? source;

  @override
  AppState reduce() => switch (linkInstall.refusedField) {
    null || 'name' => state.copyWith.linkInstall(source: source),
    _ => state.copyWith.linkInstall(
      source: source,
      refusedField: null,
      refusedSaid: null,
    ),
  };
}
