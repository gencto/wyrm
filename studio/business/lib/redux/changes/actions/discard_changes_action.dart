import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Drops every staged change and closes the review.
class DiscardChangesAction extends Action {
  @override
  AppState reduce() => state.copyWith.changes(
    table: const IMapConst({}),
    view: const IListConst([]),
    message: null,
    open: false,
  );
}
