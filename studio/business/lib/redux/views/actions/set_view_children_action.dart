import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The children of [key], a node the project's menu lists (one item per
/// child).
class SetViewChildrenAction extends Action {
  SetViewChildrenAction(this.key, this.names);

  final String key;
  final List<String> names;

  @override
  AppState? reduce() {
    final now = names.lock;
    return views.children[key] == now
        ? null
        : state.copyWith.views(children: views.children.add(key, now));
  }
}
