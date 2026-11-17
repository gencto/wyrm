import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/live/actions/set_read_failed_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/system/actions/set_filter_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/pages/explorer_page.dart';

import 'support/explorer_app.dart';
import 'support/rebuilds.dart';

/// Explorer is built again only when something it draws changed
/// (studio-rules §9): a dispatch elsewhere in the app, or a live value of a
/// key it does not show, leaves the page as it is; each part it draws (a
/// point's value, a link's dot, the tree's filter, the selection, a staged
/// change, a failed read) still reaches the screen. It prints the time of
/// one dispatch and asserts no time: machines differ.
void main() {
  setUp(() => S.load(const Locale('en')));

  Future<ExplorerApp> device(WidgetTester t) async {
    final app = ExplorerApp();
    await app.pump(t);
    await t.tap(
      find
          .byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == 'plc1',
          )
          .first,
    );
    await app.settle(t);
    expect(app.store.state.nodes.selectedNode, ExplorerApp.dev);
    return app;
  }

  LiveValue sample(int i) =>
      LiveValue(time: DateTime(2026, 11, 15, 12, 1, i), value: i);

  testWidgets('a dispatch elsewhere does not build the page again', (
    t,
  ) async {
    final app = await device(t);
    final r = await rebuilds<ExplorerPage>(
      t,
      (i) => app.store.dispatchSync(SetFilterAction('f$i')),
    );
    report('Explorer, system.filter', r);
    expect(r.built, 0);
  });

  testWidgets('a value of a key not on screen does not build it again', (
    t,
  ) async {
    final app = await device(t);
    final r = await rebuilds<ExplorerPage>(
      t,
      (i) => app.store.dispatchSync(
        SetLiveValuesAction({'wy/central/downstream/other/x': sample(i)}),
      ),
    );
    report('Explorer, a key not on screen', r);
    expect(r.built, 0);
  });

  testWidgets("a history read under way is the trend's spinner", (t) async {
    final app = await device(t);
    final s = app.store;
    await s.dispatchAndWait(SelectPointAction(ExplorerApp.temp));
    await app.settle(t);
    // the point's history read, no row yet
    s.dispatchSync(
      UpdateStateAction<AppState>.withReducer(
        (st) => st.copyWith.nodes(
          historyKey: ExplorerApp.temp,
          history: const IListConst([]),
        ),
      ),
    );
    final read = RetrieveHistoryAction(ExplorerApp.temp);
    s.dispatchSync(WaitAction.add(read));
    await t.pump();
    await t.pump();
    ExplorerPage page() => t.widget<ExplorerPage>(find.byType(ExplorerPage));
    expect(page().trend?.loading, isTrue);
    s.dispatchSync(WaitAction.remove(read));
    await t.pump();
    await t.pump();
    expect(page().trend?.loading, isFalse);
  });

  testWidgets('what the page draws builds it again', (t) async {
    final app = await device(t);
    final s = app.store;

    // a point of the device on screen: its row's value
    final point = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatchSync(SetLiveValuesAction({ExplorerApp.temp: sample(i)})),
      runs: 10,
    );
    report('Explorer, a point on screen', point);
    expect(point.built, 10);
    ExplorerPage page() => t.widget<ExplorerPage>(find.byType(ExplorerPage));
    expect(
      page().points.firstWhere((p) => p.id == ExplorerApp.temp).value,
      '9',
    );

    // a link's state: the dot of its tree row
    final dot = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({
          '${ExplorerApp.root}/sys/links/opc/state': LiveValue(
            time: DateTime(2026, 11, 15, 12, 2, i),
            value: i.isEven ? 2 : 5,
          ),
        }),
      ),
      runs: 4,
    );
    expect(dot.built, 4);

    // a failed read: the mark of its row
    final failed = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatchSync(SetReadFailedAction(ExplorerApp.mode, 'e$i')),
      runs: 3,
    );
    expect(failed.built, 3);
    expect(
      page().points.firstWhere((p) => p.id == ExplorerApp.mode).failed,
      'e2',
    );

    // a staged value: the staged mark of the point
    final staged = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatchSync(StageValueAction.entered(ExplorerApp.temp, 30 + i)),
      runs: 3,
    );
    expect(staged.built, greaterThan(0));

    // the tree's filter
    final filter = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatchSync(SetTreeFilterAction(i.isEven ? 'plc' : '')),
      runs: 4,
    );
    expect(filter.built, 4);
    expect(page().treeFilter, '');

    // the selection: another node, then the device again
    final select = await rebuilds<ExplorerPage>(
      t,
      (i) => s.dispatch(
        SelectNodeAction(i.isEven ? ExplorerApp.conn : ExplorerApp.dev),
      ),
      runs: 2,
    );
    expect(select.built, 2);
    expect(page().keyName, ExplorerApp.dev);
    await app.settle(t);
  });
}
