import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// *Clear all*: forgets every problem of this session and its toasts.
class ClearProblemsAction extends Action {
  @override
  AppState reduce() => state.copyWith.problems(
    items: const IListConst([]),
    toasts: const IListConst([]),
    unread: 0,
  );
}
