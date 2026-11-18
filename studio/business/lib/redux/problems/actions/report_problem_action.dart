import 'package:logging/logging.dart';
import 'package:models/studio_error.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'add_problem_action.dart';

final _log = Logger('problems');

/// A failure reported from where no state may change at once: a widget
/// that threw while the tree is being built, the store's own error
/// observer while an action ends. Its reducer is asynchronous, so the
/// failure is in Problems (as [AddProblemAction] puts it) once what was
/// under way has ended; whoever reports it dispatches and returns.
///
/// A failure of this action is written to the log and goes no further: it
/// must not report itself.
class ReportProblemAction extends Action {
  ReportProblemAction(this.error);

  final StudioError error;

  @override
  Future<AppState?> reduce() async => problemAdded(state, error);

  @override
  Object? wrapError(Object error, StackTrace stackTrace) {
    _log.severe('a failure could not be added to Problems', error);
    return null;
  }
}
