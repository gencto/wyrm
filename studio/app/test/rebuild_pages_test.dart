import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/pages/links_page.dart';
import 'package:ui/pages/system_page.dart';

import 'support/links_app.dart' as links;
import 'support/rebuilds.dart';
import 'support/system_app.dart' as system;

/// System, Links and the toast stack over every page are built again only
/// when something they draw changed (studio-rules §9): a dispatch elsewhere
/// or a live value of a key not on screen leaves them as they are; a value
/// they show, or a new toast, still reaches the screen. It prints the time
/// of one dispatch and asserts no time.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  LiveValue sample(Object v) =>
      LiveValue(time: DateTime.utc(2026, 11, 12, 2, 3), value: v);

  testWidgets('System: only what it draws builds it again', (t) async {
    final app = system.SystemApp();
    await app.pump(t);
    final s = app.store;

    final filter = await rebuilds<SystemPage>(
      t,
      (i) => s.dispatchSync(SetTreeFilterAction('q$i')),
    );
    report('System, nodes.treeFilter', filter);
    expect(filter.built, 0);

    final live = await rebuilds<SystemPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'wy/plant/downstream/other/x': sample(i)}),
      ),
    );
    report('System, a key not on screen', live);
    expect(live.built, 0);

    final version = await rebuilds<SystemPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'${system.sys}/version': sample('0.2.$i')}),
      ),
      runs: 3,
    );
    expect(version.built, 3);
  });

  testWidgets('Links: only what it draws builds it again', (t) async {
    final app = links.LinksApp();
    await app.pump(t);
    final s = app.store;

    final filter = await rebuilds<LinksPage>(
      t,
      (i) => s.dispatchSync(SetTreeFilterAction('q$i')),
    );
    report('Links, nodes.treeFilter', filter);
    expect(filter.built, 0);

    final live = await rebuilds<LinksPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'wy/plant/downstream/other/x': sample(i)}),
      ),
    );
    report('Links, a key not on screen', live);
    expect(live.built, 0);

    final state = await rebuilds<LinksPage>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({
          '${links.sys}/links/modbus/state': sample(i.isEven ? 5 : 2),
        }),
      ),
      runs: 4,
    );
    expect(state.built, 4);
  });

  testWidgets('the toast stack: only a toast builds it again', (t) async {
    final app = system.SystemApp();
    await app.pump(t, toasts: true);
    final s = app.store;

    final filter = await rebuilds<ToastStack>(
      t,
      (i) => s.dispatchSync(SetTreeFilterAction('q$i')),
    );
    report('Toast stack, nodes.treeFilter', filter);
    expect(filter.built, 0);

    final live = await rebuilds<ToastStack>(
      t,
      (i) => s.dispatchSync(
        SetLiveValuesAction({'${system.sys}/version': sample('0.1.$i')}),
      ),
    );
    expect(live.built, 0);

    final toast = await rebuilds<ToastStack>(
      t,
      (i) => s.dispatchSync(ShowNoticeAction('Done $i')),
      runs: 2,
    );
    expect(toast.built, 2);
    expect(find.text('Done 1'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });
}
