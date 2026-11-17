import 'package:business/redux/assistant/actions/set_draft_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/system/actions/set_filter_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/assistant/assistant_drawer.dart';
import 'package:ui/pages/assistant_page.dart';

import 'support/assistant_app.dart';
import 'support/explorer_app.dart';
import 'support/rebuilds.dart';

/// The Assistant, as the tab and as the drawer over Explorer, is built
/// again only when something it draws changed (studio-rules §9): a dispatch
/// elsewhere, or a live value of a key not on screen, leaves it as it is;
/// the ask box it draws still follows the draft. It prints the time of one
/// dispatch and asserts no time.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  LiveValue sample(int i) =>
      LiveValue(time: DateTime(2026, 11, 15, 12, 1, i), value: i);

  testWidgets('the tab: only what it draws builds it again', (t) async {
    final app = AssistantApp()..task('t-1', planRecord());
    await app.pump(t, selected: 't-1');
    final s = app.store;

    final filter = await rebuilds<AssistantPage>(
      t,
      (i) => s.dispatchSync(SetFilterAction('f$i')),
    );
    report('Assistant, system.filter', filter);
    expect(filter.built, 0);

    final tree = await rebuilds<AssistantPage>(
      t,
      (i) => s.dispatchSync(SetTreeFilterAction('q$i')),
    );
    expect(tree.built, 0);

    final live = await rebuilds<AssistantPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'wy/central/downstream/other/x': sample(i)}),
      ),
    );
    report('Assistant, a key not on screen', live);
    expect(live.built, 0);

    final draft = await rebuilds<AssistantPage>(
      t,
      (i) => s.dispatchSync(SetDraftAction('add ahu$i')),
      runs: 5,
    );
    report('Assistant, the draft', draft);
    expect(draft.built, 5);
    expect(
      t.widget<AssistantPage>(find.byType(AssistantPage)).composer.draft,
      'add ahu4',
    );
  });

  testWidgets('the drawer over Explorer: only what it draws builds it', (
    t,
  ) async {
    final app = ExplorerApp();
    await app.pump(t);
    app.store.dispatchSync(SetDrawerAction(open: true));
    await app.settle(t);
    expect(find.byType(AssistantDrawer), findsOneWidget);
    final s = app.store;

    final filter = await rebuilds<AssistantDrawer>(
      t,
      (i) => s.dispatchSync(SetFilterAction('f$i')),
    );
    report('Assistant drawer, system.filter', filter);
    expect(filter.built, 0);

    final live = await rebuilds<AssistantDrawer>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'wy/central/downstream/other/x': sample(i)}),
      ),
    );
    expect(live.built, 0);

    final draft = await rebuilds<AssistantDrawer>(
      t,
      (i) => s.dispatchSync(SetDraftAction('ask $i')),
      runs: 5,
    );
    expect(draft.built, 5);
    expect(
      t.widget<AssistantDrawer>(find.byType(AssistantDrawer)).composer.vm.draft,
      'ask 4',
    );
  });
}
