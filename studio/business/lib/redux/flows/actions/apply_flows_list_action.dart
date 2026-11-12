import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/flow_value_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../services/live_lists/live_lists_dispatcher.dart';
import 'retrieve_flow_defs_action.dart';

/// One update of the live list of `dataflows`: a flow not in the table is
/// added (its state from the live `~val` held, its definition read once,
/// `RetrieveFlowDefsAction`), one gone leaves the table (and the
/// selection), a changed one takes its new name. Rows already held are
/// kept as they are: nothing is read again for them. An update of another
/// site than the one on screen is dropped.
class ApplyFlowsListAction extends Action {
  ApplyFlowsListAction(this.parent, this.change);

  final String parent;
  final ListChange change;

  final _read = <String>[];

  @override
  AppState? reduce() {
    final root = site.root;
    if (root == null || parent != '$root/dataflows') {
      return null;
    }
    var table = flows.table;
    var view = flows.view;
    FlowSummary fresh(Child c) {
      _read.add(c.name);
      final f = flowSummaryOfValue(
        c.name,
        live.values['$parent/${c.name}']?.value,
        description: c.meta.displayName,
      );
      return f;
    }

    if (change.children case final all?) {
      final next = <String, FlowSummary>{};
      for (final c in all) {
        next[c.name] = switch (table[c.name]) {
          final f? => f.copyWith(description: c.meta.displayName),
          null => fresh(c),
        };
      }
      table = next.lock;
      view = next.keys.toIList();
    } else if (change.child case final c?) {
      final f = table[c.name];
      if (f == null) {
        table = table.add(c.name, fresh(c));
        view = view.add(c.name);
      } else if (f.description != c.meta.displayName) {
        table = table.add(c.name, f.copyWith(description: c.meta.displayName));
      } else {
        return null;
      }
    } else {
      final gone = change.name!;
      if (!table.containsKey(gone)) {
        return null;
      }
      table = table.remove(gone);
      view = view.remove(gone);
    }
    return state.copyWith.flows(
      table: table,
      view: view,
      selectedFlow: table.containsKey(flows.selectedFlow ?? '')
          ? flows.selectedFlow
          : null,
    );
  }

  @override
  void after() {
    super.after();
    if (_read.isNotEmpty) {
      unawaited(dispatchAndWait(RetrieveFlowDefsAction(_read.toList())));
    }
  }
}
