import 'package:models/install_source.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetSourceAction extends Action {
  SetSourceAction(this.source);

  final InstallSource? source;

  @override
  AppState reduce() => state.copyWith.linkInstall(source: source);
}
