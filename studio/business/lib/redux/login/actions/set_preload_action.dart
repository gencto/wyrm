import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Moves the welcome's preload on (docs/design/specs/login.md §5): [step] is
/// the one running (0 the tree, 1 the flows, 2 the flow blocks, 3 the links,
/// 4 the sites; 5 all done) and [late] the ones that did not finish in time
/// or failed — they go on, or are read again, after Studio opens.
class SetPreloadAction extends Action {
  SetPreloadAction(this.step, {this.late = const []});

  final int step;
  final List<int> late;

  @override
  AppState reduce() =>
      state.copyWith.login(preload: step, preloadLate: late.lock);
}
