import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/common/app_store.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/common.dart';

import '../../../business/test/support/fake_wyrm.dart';

export '../../../business/test/support/fake_wyrm.dart';

/// The site of every screen test.
const plant = 'wy/plant';

/// One workspace over a fake gateway, logged in as `olena` on `plant`:
/// a test lays the site's tables in with [put], pumps the connector with
/// [pump], reads every word with [words] and what reached the broker with
/// [calls].
class ScreenApp {
  ScreenApp({bool config = true, List<(String, String)>? grants})
    : login = FakeLogin(
        session: FakeSession(
          who: WhoAmI(
            subject: 'user:olena',
            site: 'plant',
            roles: const ['admin'],
            max: 'config',
            grants: grants ?? [('$plant/**', config ? 'config' : 'read')],
          ),
        ),
      ) {
    store = fakeStore(login: login);
  }

  final FakeLogin login;
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;
  FakeSession get session => login.session;

  /// What the clipboard was given last.
  String? clipboard;

  /// Logs in (the session reads `/api/me`).
  Future<void> logIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
    });
  }

  /// Pumps [child] in [locale] over the store, in the dark theme.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
  }) async {
    await S.load(locale);
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: AppStore(
          store: store,
          child: MaterialApp(
            theme: darkTheme(),
            locale: locale,
            supportedLocales: S.delegate.supportedLocales,
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Studio's own shell and router on [workspace], so a screen's links
  /// switch the workspace as they do in the app. The router is built once
  /// per test file ([createAppRouter]): call this once per file.
  Future<void> pumpInStudio(
    WidgetTester tester,
    PageRouteInfo workspace,
  ) async {
    await S.load(const Locale('en'));
    createAppRouter(store);
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: AppStore(
          store: store,
          child: MaterialApp.router(
            routerConfig: appRouter.config(),
            theme: darkTheme(),
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
          ),
        ),
      ),
    );
    await settle(tester);
    await go(tester, workspace);
  }

  /// To [workspace] of the shell.
  Future<void> go(WidgetTester tester, PageRouteInfo workspace) async {
    unawaited(appRouter.navigate(StudioRoute(children: [workspace])));
    await settle(tester);
  }

  /// The route on top (its name).
  String get top => appRouter.topRoute.name;

  /// Lets the fake broker's answers arrive and the screen follow them, in
  /// [rounds] of 100 ms of the clock (a read that collects values for a
  /// while needs more of them).
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Takes the screen off (its timers stop, it unwatches).
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  /// Every word under [of], in the order of the tree, then the tooltips
  /// (a disabled control's reason is one); none from inside a [without]
  /// (a trend, whose times follow the clock).
  List<String> words(WidgetTester tester, Finder of, {Type? without}) {
    bool kept(Element e) =>
        without == null ||
        !e
            .debugGetDiagnosticChain()
            .skip(1)
            .any(
              (a) => a.widget.runtimeType == without,
            );
    Iterable<W> all<W extends Widget>() => [
      for (final e
          in find.descendant(of: of, matching: find.byType(W)).evaluate())
        if (kept(e)) e.widget as W,
    ];
    return [
      for (final w in all<RichText>()) w.text.toPlainText(),
      for (final w in all<SelectableText>())
        'selectable: ${w.data ?? w.textSpan?.toPlainText()}',
      for (final w in all<Tooltip>())
        if (w.message ?? w.richMessage?.toPlainText() case final m?
            when m.isNotEmpty)
          'tip: $m',
    ];
  }

  /// The calls of [action] (an invoke's name, or `children`, `meta`) made
  /// so far.
  List<Call> calls(String action) => [
    for (final c in api.calls)
      if (c.action == action || (c.action == null && c.op == action)) c,
  ];

  /// A row that overflows its box is drawn as it is and not reported
  /// (the review panel's buttons do at the test's text scale); every other
  /// error still fails the test.
  void ignoreOverflow() {
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('overflowed')) {
        return;
      }
      report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
  }

  /// Lays [change] into the store, as the test needs it.
  void put(AppState Function(AppState) change) =>
      store.dispatchSync(_Put(change));
}

/// Lays a state in, as the test needs it.
class _Put extends ReduxAction<AppState> {
  _Put(this.change);

  final AppState Function(AppState) change;

  @override
  AppState reduce() => change(state);
}

/// The words a screen showed in each state, kept in
/// `test/support/words/<screen>.json`: written once with `WORDS_DUMP=1`
/// from the connector as it was before studio-rules (2026-11-15), and not
/// regenerated since — a change there is a change of what the screen says.
///
/// `WORDS_DUMP=1 flutter test test/<screen>_test.dart` writes the words it
/// sees to `<tmp>/<screen>_words.json` instead of comparing them.
final class ScreenWords {
  ScreenWords(this.screen) {
    final file = File('test/support/words/$screen.json');
    if (file.existsSync()) {
      for (final MapEntry(:key, :value) in (jsonDecode(
        file.readAsStringSync(),
      ) as Map<String, Object?>).entries) {
        _expected[key] = [for (final w in value! as List<Object?>) '$w'];
      }
    }
    tearDownAll(() {
      if (dump) {
        File('${Directory.systemTemp.path}/${screen}_words.json')
            .writeAsStringSync(
              '${const JsonEncoder.withIndent('  ').convert(_dumped)}\n',
            );
      }
    });
  }

  final String screen;
  final _expected = <String, List<String>>{};
  final _dumped = <String, List<String>>{};

  /// Writing the words, not comparing them.
  final dump = Platform.environment['WORDS_DUMP'] == '1';

  /// [got] are the words of the state [name].
  void check(String name, List<String> got) {
    if (dump) {
      _dumped[name] = got;
      return;
    }
    expect(got, _expected[name], reason: name);
  }
}
