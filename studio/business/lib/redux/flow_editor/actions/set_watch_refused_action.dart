import 'package:wyrm_client/wyrm_client.dart' show Status;

import '../../app_state.dart';
import '../../common/action.dart';

class SetWatchRefusedAction extends Action {
  SetWatchRefusedAction(this.watchRefused);

  final Status? watchRefused;

  @override
  AppState reduce() => state.copyWith.flowEditor(watchRefused: watchRefused);
}
