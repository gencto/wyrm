import 'package:models/live_value.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/apply_flow_values_action.dart';
import '../../historian/actions/append_samples_action.dart';
import '../../problems/actions/resolve_stream_action.dart';
import 'set_live_values_action.dart';

/// One batch of the live values service ([changed]: the changed keys only;
/// a null value removes the key), up to five a second: the values, the
/// screens that follow values beyond showing them (History's trend grows,
/// Flows reads a definition whose version changed; each does nothing while
/// its tab is hidden) and the streams that are back, in one state, so each
/// connector follows a batch once.
class ApplyLiveValuesAction extends Action {
  ApplyLiveValuesAction(this.changed);

  final Map<String, LiveValue?> changed;

  @override
  AppState? reduce() {
    if (changed.isEmpty) {
      return null;
    }
    final before = state;
    dispatchSync(SetLiveValuesAction(changed), notify: false);
    dispatchSync(AppendSamplesAction(changed), notify: false);
    dispatchSync(ApplyFlowValuesAction(changed), notify: false);
    // Values from a site whose stream was down: it is back.
    final problems = state.problems;
    final down = {
      for (final e in problems.items)
        if (e.stream case final s? when problems.toasts.contains(e.id)) s,
    };
    for (final site in {for (final k in changed.keys) ?siteOf(k)}) {
      if (down.contains(site)) {
        dispatchSync(ResolveStreamAction(site), notify: false);
      }
    }
    return identical(state, before) ? null : state;
  }
}
