import 'dart:async';

import 'package:models/live_value.dart';

import '../../../wyrm/mappers/flow_value_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_flow_defs_action.dart';

/// New `~val`s of flows ([changed], one batch of `LiveValuesService`)
/// while Flows is shown: a flow whose live `version` is not the one its
/// row's definition belongs to is read again (`RetrieveFlowDefsAction`),
/// unless that read is already running. The state, the deployer and the
/// error are not copied here: the screen shows them from `live.values`.
class ApplyFlowValuesAction extends Action {
  ApplyFlowValuesAction(this.changed);

  final Map<String, LiveValue?> changed;

  final _read = <String>[];

  @override
  AppState? reduce() {
    final root = site.root;
    if (flows.follow == null || root == null) {
      return null;
    }
    final base = '$root/dataflows/';
    for (final MapEntry(:key, :value) in changed.entries) {
      if (value == null || !key.startsWith(base)) {
        continue;
      }
      final id = key.substring(base.length);
      final row = flows.table[id];
      if (id.contains('/') || row == null) {
        continue;
      }
      final version = flowSummaryOfValue(id, value.value).version;
      if (version != row.version &&
          !state.wait.isWaiting(RetrieveFlowDefsAction.reading, ref: id)) {
        _read.add(id);
      }
    }
    return null;
  }

  @override
  void after() {
    super.after();
    if (_read.isNotEmpty) {
      unawaited(dispatchAndWait(RetrieveFlowDefsAction(_read.toList())));
    }
  }
}
