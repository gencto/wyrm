import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/login_failure.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Moves the log-in on: the step it is at (0 reaching the gateway, 1 checking
/// the user and the password, 2 reading the role and the sites) and, when it
/// failed, why (docs/design/specs/login.md §5). A new step clears a failure.
class SetLoginProgressAction extends Action {
  SetLoginProgressAction({
    this.step = 0,
    this.failure,
    this.reason,
    this.probes = const {},
  });

  final int step;
  final LoginFailure? failure;

  /// What the gateway or the network said, for the unreachable alert.
  final String? reason;

  /// Probe results to add to `login.probes` (milliseconds, -1 no answer).
  final Map<String, int> probes;

  @override
  AppState reduce() => state.copyWith.login(
    step: step,
    failure: failure,
    reason: reason,
    probes: state.login.probes.addAll(probes.lock),
  );
}
