import 'package:app/app.dart';
import 'package:app/common/app_store.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/error_kind.dart';
import 'package:models/link_info.dart';
import 'package:models/node_info.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_relation.dart';
import 'package:models/staged_change.dart';
import 'package:models/studio_error.dart';
import 'package:ui/overlays/account_menu.dart';
import 'package:ui/overlays/problems_drawer.dart';
import 'package:ui/overlays/review_panel.dart';
import 'package:ui/overlays/search_palette.dart';
import 'package:ui/shell/top_bar.dart';
import 'package:ui/shell/workspace_rail.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/screen_app.dart';

/// The Studio shell as the store makes it (studio-rules, step 1): the
/// words of the top bar, the rail, the Problems drawer and the review
/// panel, in English and Ukrainian, and what each of their controls does —
/// the workspace on screen, the site viewed, the staged changes, the
/// problems, the language and the theme, the log-out. One test, because
/// the app's router is built once per test file.
void main() {
  final words = ScreenWords('studio');

  testWidgets('the shell, its drawers and its controls', (t) async {
    final app = ScreenApp(
      grants: [('$plant/downstream/**', 'write'), ('$plant/**', 'read')],
    );
    await app.logIn(t);
    app
      ..ignoreOverflow()
      ..api.invokes['$plant/downstream/plc1/t1 ▸ reset'] = const [VNull()]
      ..put(
        (s) => s.copyWith(
          site: s.site.copyWith(
            connected: true,
            choices: IList(const [
              SiteChoice(site: 'plant'),
              SiteChoice(site: 'central', relation: SiteRelation.upstream),
              SiteChoice(
                site: 'line3',
                relation: SiteRelation.downstream,
                via: 'line1',
              ),
            ]),
          ),
          links: s.links.copyWith(
            table: IMap(const {
              'modbus': LinkInfo(id: 'modbus', driver: 'modbus'),
            }),
            view: ['modbus'].lock,
          ),
          quarantine: s.quarantine.copyWith(
            table: IMap(const {
              'field-x': QuarantineEntry(cn: 'link:field-x', node: 'field-x'),
            }),
            view: ['field-x'].lock,
          ),
          nodes: s.nodes.copyWith(
            table: IMap(const {
              '$plant/downstream/plc1/t1': NodeInfo(
                key: '$plant/downstream/plc1/t1',
                name: 't1',
                display: 'Boiler temperature',
              ),
            }),
            view: ['$plant/downstream/plc1/t1'].lock,
          ),
          changes: s.changes.copyWith(
            table: IMap(const {
              'c1': StagedChange(
                id: 'c1',
                op: ChangeOp.edit,
                key: '$plant/downstream/plc1/sp',
                field: 'value',
                from: ChangeSide.text('20'),
                to: ChangeSide.text('21.5'),
                level: Perm.write,
              ),
              'c2': StagedChange(
                id: 'c2',
                op: ChangeOp.edit,
                key: '$plant/sys/links/modbus',
                field: 'params',
                to: ChangeSide.text('poll_s 5'),
                level: Perm.config,
              ),
            }),
            view: ['c1', 'c2'].lock,
          ),
          problems: s.problems.copyWith(
            items: IList([
              StudioError(
                kind: ErrorKind.reach,
                id: 7,
                message: 'timeout',
                key: '$plant/downstream/plc1/t1',
                call: const .known(.history),
                at: DateTime(2026, 11, 12, 2, 1),
                quiet: true,
              ),
            ]),
            unread: 1,
          ),
        ),
      );

    createAppRouter(app.store);
    // as run_env wires it: the error dialogs open over the router
    NavigateAction.setNavigatorKey(appRouter.navigatorKey);
    await t.pumpWidget(
      StoreProvider<AppState>(
        store: app.store,
        child: AppStore(
          store: app.store,
          child: AppConnector(routerConfig: appRouter.config()),
        ),
      ),
    );
    await app.settle(t);
    await app.go(t, const FlowsRoute());
    expect(app.top, FlowsRoute.name);

    // the palette, whatever its id type
    final palette = find.byWidgetPredicate((w) => w is SearchPalette);

    List<String> shell() => [
      ...app.words(t, find.byType(TopBar)),
      ...app.words(t, find.byType(WorkspaceRail)),
    ];

    words.check('shell', shell());

    // the rail
    await t.tap(
      find.descendant(
        of: find.byType(WorkspaceRail),
        matching: find.text('History'),
      ),
    );
    await app.settle(t);
    expect(app.top, HistoryRoute.name);
    await t.tap(
      find.descendant(
        of: find.byType(WorkspaceRail),
        matching: find.text('Flows'),
      ),
    );
    await app.settle(t);
    expect(app.top, FlowsRoute.name);

    // the Problems drawer
    await t.tap(find.text('1 problem'));
    await app.settle(t);
    expect(app.store.state.problems.open, isTrue);
    words.check('problems', app.words(t, find.byType(ProblemsDrawer)));
    await t.tap(
      find.descendant(
        of: find.byType(ProblemsDrawer),
        matching: find.text('Clear all'),
      ),
    );
    await app.settle(t);
    expect(app.store.state.problems.items, isEmpty);
    words.check('problems cleared', app.words(t, find.byType(ProblemsDrawer)));
    await t.tap(
      find.byKey(const ValueKey('problems-close')),
    );
    await app.settle(t);
    expect(app.store.state.problems.open, isFalse);

    // the review panel
    await t.tap(
      find.descendant(
        of: find.byType(TopBar),
        matching: find.textContaining('Review'),
      ),
    );
    await app.settle(t);
    expect(app.store.state.changes.open, isTrue);
    words.check('review', app.words(t, find.byType(ReviewPanel)));
    await t.tap(
      find
          .descendant(
            of: find.byType(ChangeCard),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await app.settle(t);
    expect(app.store.state.changes.view, ['c2']);
    words.check('review one', app.words(t, find.byType(ReviewPanel)));
    await t.tap(
      find.descendant(
        of: find.byType(ReviewPanel),
        matching: find.text('Discard all'),
      ),
    );
    await app.settle(t);
    expect(app.store.state.changes.view, isEmpty);
    // Discard all closes the panel too
    expect(app.store.state.changes.open, isFalse);

    // search: a workspace, a site, a key
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await app.settle(t);
    words.check('search', app.words(t, palette));
    await t.tap(
      find.descendant(
        of: palette,
        matching: find.text('Access'),
      ),
    );
    await app.settle(t);
    expect(app.top, AccessRoute.name);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await app.settle(t);
    await t.enterText(
      find.descendant(
        of: palette,
        matching: find.byType(TextField),
      ),
      'downstream/plc1/t9',
    );
    await app.settle(t);
    words.check('search go to', app.words(t, palette));
    await t.tap(find.text('Go to downstream/plc1/t9'));
    await app.settle(t);
    expect(app.top, ExplorerRoute.name);
    expect(app.store.state.nodes.selectedNode, '$plant/downstream/plc1/t9');

    // the site switcher (the shell read the sites when it opened)
    app.put(
      (s) => s.copyWith.site(
        choices: IList(const [
          SiteChoice(site: 'plant'),
          SiteChoice(site: 'central', relation: SiteRelation.upstream),
          SiteChoice(
            site: 'line3',
            relation: SiteRelation.downstream,
            via: 'line1',
          ),
        ]),
      ),
    );
    await app.settle(t);
    await t.tap(
      find.descendant(of: find.byType(TopBar), matching: find.text('plant')),
    );
    await app.settle(t);
    words.check('sites menu', [
      for (final w in t.widgetList<RichText>(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.byType(RichText),
        ),
      ))
        w.text.toPlainText(),
    ]);
    await t.tap(find.text('central').last);
    await app.settle(t);
    expect(app.store.state.site.current, 'central');
    words.check('shell central', shell());
    // the fake gateway knows nothing of central: its reads fail in dialogs
    appRouter.navigatorKey.currentState!.popUntil(
      (r) => r is! RawDialogRoute,
    );
    await app.settle(t);

    // the account menu: theme and language
    await t.tap(find.text('OL'));
    await app.settle(t);
    words.check('account menu', app.words(t, find.byType(AccountMenu)));
    await t.tap(find.bySemanticsLabel(S.current.lightTheme).last);
    await app.settle(t);
    expect(app.store.state.theme.mode, ThemeMode.light);
    await t.tap(find.text('Українська'));
    await app.settle(t);
    expect(app.store.state.language.locale, 'uk');
    await t.tapAt(Offset.zero);
    await app.settle(t);
    words.check('shell uk', shell());

    // log out: the log-in page
    await t.tap(find.text('OL'));
    await app.settle(t);
    await t.tap(find.text(S.current.logOut));
    await app.settle(t);
    expect(app.top, LogInRoute.name);
    expect(app.store.state.session.token, isNull);
    await S.load(const Locale('en'));
    await app.leave(t);
  });
}
