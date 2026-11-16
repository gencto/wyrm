import 'package:models/live_value.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/apply_flow_values_action.dart';
import '../../flows/actions/retrieve_flow_defs_action.dart';
import '../../historian/actions/append_samples_action.dart';
import '../../problems/actions/resolve_stream_action.dart';
import 'set_live_values_action.dart';

/// One batch of the live values service ([changed]: the changed keys only;
/// a null value removes the key), up to five a second: the values, the
/// screens that follow values beyond showing them (History's trend grows,
/// Flows learns which definitions to read again; each does nothing while
/// its tab is hidden) and the streams that are back, in one state, so each
/// connector follows a batch once. The definitions a new version needs are
/// read next, awaited here; this action changes no state itself (`null`).
class ApplyLiveValuesAction extends Action {
  ApplyLiveValuesAction(this.changed);

  final Map<String, LiveValue?> changed;

  @override
  Future<AppState?> reduce() async {
    if (changed.isEmpty) {
      return null;
    }
    dispatchSync(AppendSamplesAction(changed), notify: false);
    final flows = ApplyFlowValuesAction(changed);
    dispatchSync(flows, notify: false);
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
    // The values last: the one step that notifies, for all of the above.
    dispatchSync(SetLiveValuesAction(changed));
    if (flows.unread.isNotEmpty) {
      await dispatchAndWait(RetrieveFlowDefsAction(flows.unread));
    }
    return null;
  }
}
