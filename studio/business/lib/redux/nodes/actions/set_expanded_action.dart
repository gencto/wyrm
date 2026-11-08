import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetExpandedAction extends Action {
  SetExpandedAction(this.expanded);

  final ISet<String> expanded;

  @override
  AppState reduce() => state.copyWith.nodes(expanded: expanded);
}
