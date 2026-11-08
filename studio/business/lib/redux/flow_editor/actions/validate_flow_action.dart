import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class ValidateFlowAction extends Action with Debounce {
  // TODO(frx): tune the pause that must elapse before the action runs.
  @override
  int get debounce => 300; // milliseconds

  // One lock per action type. Override lockBuilder() to give each
  // instance its own: Object? lockBuilder() => someId;

  // TODO(frx): do async work, then return a new state (or null for none).
  @override
  Future<AppState?> reduce() async => null;
}
