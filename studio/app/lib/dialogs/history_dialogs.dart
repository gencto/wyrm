import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/reread_trend_action.dart';
import 'package:business/wyrm/historian_stats.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/history_screen.dart';

import '../common/app_store.dart';
import '../mappers/history_mappers.dart';
import 'node_action_dialog.dart';

/// The selectors over the store's state now.
class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

/// Asks for [act] of History (its `+`, a row of its inspector): the form
/// of the node's action, or a confirmation for one that removes; once it
/// went through, the trend is read again ([RereadTrendAction]).
Future<void> askHistory(BuildContext context, HistoryAct act) {
  final call = act.call;
  final key = _Sel(AppStore.of(context).state).historyKeyOf(call.node);
  return runNodeAction(
    context,
    key,
    call.wire,
    confirm: switch (act) {
      HistoryAct.remove => S.current.removeGroupNote,
      HistoryAct.unsubscribe => S.current.unsubscribeNote,
      HistoryAct.addGroup ||
      HistoryAct.addPath ||
      HistoryAct.edit ||
      HistoryAct.purge => null,
    },
    then: RereadTrendAction.new,
  );
}
