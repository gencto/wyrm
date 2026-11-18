import 'package:logging/logging.dart';
import 'package:models/studio_error.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'add_problem_action.dart';

final _log = Logger('problems');

/// A fault no action caught (a widget that threw while it was built, a
/// callback, a future nobody awaited), reported by the app's fault handlers
/// (`app/lib/faults.dart`), which wait for nothing: they dispatch this and
/// return. It goes into Problems as [AddProblemAction] puts it, and to the
/// log (its line, without secrets).
///
/// A part that throws on every build would report itself on every frame,
/// and each report changes the state the part is built from: a failure
/// that is the same line of Problems as one taken less than [repeatWithin]
/// before is not taken again, so nothing changes and nothing is built for
/// it.
///
/// A failure of this action is written to the log and goes no further: it
/// must not report itself.
class ReportProblemAction extends Action {
  ReportProblemAction(this.error);

  final StudioError error;

  /// How soon the same fault is taken again.
  static const repeatWithin = Duration(seconds: 2);

  @override
  AppState? reduce() {
    final next = problemAdded(
      state,
      error.copyWith(at: error.at ?? deps.clock()),
      repeatAfter: repeatWithin,
    );
    if (next != null) {
      _log.warning('uncaught: ${error.report?.line ?? error.kind.name}');
    }
    return next;
  }

  @override
  Object? wrapError(Object error, StackTrace stackTrace) {
    _log.severe('a failure could not be added to Problems', error);
    return null;
  }
}
