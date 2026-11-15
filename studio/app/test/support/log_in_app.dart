import 'dart:convert';
import 'dart:io';

import 'package:app/connectors/lock_overlay_connector.dart';
import 'package:app/connectors/log_in_page_connector.dart';
import 'package:app/connectors/step_up_dialog_connector.dart';
import 'package:app/run_env.dart' show devicePrompts;
import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/enable_device_action.dart';
import 'package:business/redux/device/actions/load_device_action.dart';
import 'package:business/redux/device/actions/offer_device_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:business/wyrm/session.dart';
import 'package:device_key/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:storage/storage.dart';
import 'package:ui/overlays/lock_overlay.dart';
import 'package:ui/overlays/step_up_dialog.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_discovery.dart';
import '../../../business/test/support/fake_wyrm.dart';
import '../../../business/test/support/test_tls.dart';

export '../../../business/test/support/fake_discovery.dart';
export '../../../business/test/support/fake_wyrm.dart';

/// The gateway of every log-in test, and its user.
const gw = 'https://plant.local:8446';
const standbyGw = 'https://edge.local:8446';
const user = 'olena';
const password = 'wyrm-demo-1';

/// The test CA (`test_tls.dart`) as DER: the CA a found gateway sends, so
/// the code the trust card shows is the one Studio computes from it.
final Uint8List testCaDer = base64Decode(
  testCaPem
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join(),
);

/// Loads `ui`'s bundled fonts under the names `ui` uses, as its golden
/// tests do: the page is laid out in its real type, not the test font,
/// whose wide squares overflow lines the design fits.
Future<void> loadFonts() async {
  final dir = [
    '../ui/assets/fonts',
    'ui/assets/fonts',
  ].map(Directory.new).firstWhere((d) => d.existsSync());
  final families = {
    'packages/ui/IBM Plex Sans': [
      'IBMPlexSans-Regular.ttf',
      'IBMPlexSans-Medium.ttf',
      'IBMPlexSans-SemiBold.ttf',
    ],
    'packages/ui/IBM Plex Mono': [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-Medium.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ],
    'packages/ui/Unbounded': ['Unbounded.ttf'],
    'Roboto': ['IBMPlexSans-Regular.ttf'],
  };
  for (final MapEntry(:key, :value) in families.entries) {
    final loader = FontLoader(key);
    for (final f in value) {
      final bytes = File('${dir.path}/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// What the gateway `plant` says on `/api/info`.
const plantInfo = GatewayInfo(
  site: 'plant',
  version: '0.1.0',
  tls: true,
  devices: DevicePolicy(enabled: true),
);

/// One computer at the log-in page, the lock or the step-up: its settings,
/// its key store, a gateway that checks every signature, the local network
/// with its browse and `/api/info`, and the store over them.
class LogInApp {
  LogInApp({
    FakeDeviceKey? keys,
    FakeLogin? login,
    FakeInfo? net,
    List<Announcement> found = const [],
    InMemoryKeyValueStorage? settings,
    GatewayProbe answer = const GatewayProbe.answered(12),
    GatewayInfo? info = plantInfo,
  }) : keys = keys ?? FakeDeviceKey(),
       login =
           login ??
           (FakeLogin(
             answer: answer,
             session: FakeSession(
               who: identityOf(
                 subject: 'user:olena',
                 site: 'plant',
                 roles: ['engineer'],
                 max: 'config',
               ),
               devices: FakeDevices(
                 site: 'plant',
                 origin: gw,
               ),
             ),
           )..info_ = info),
       net = net ?? FakeInfo(),
       settings = settings ?? InMemoryKeyValueStorage(),
       browser = FakeBrowser(found) {
    store = Store<AppState>(
      initialState: AppState.initial(),
      dependencies: (s) => AppDependencies(
        s,
        this.settings,
        login: this.login,
        deviceKey: this.keys,
        gatewayInfo: this.net,
        browser: browser,
        browseDuration: Duration.zero,
        prompts: devicePrompts,
      ),
    );
  }

  final FakeDeviceKey keys;
  final FakeLogin login;
  final FakeInfo net;
  final FakeBrowser browser;
  final InMemoryKeyValueStorage settings;
  late final Store<AppState> store;

  FakeDevices get gateway => login.session.gateway;

  /// The gateway, the user and the password in the store.
  Future<void> fill({String gateway = gw}) async {
    await store.dispatchAndWait(SetGatewayAction(gateway));
    await store.dispatchAndWait(SetUserAction(user));
    await store.dispatchAndWait(SetPasswordAction(password));
  }

  /// A computer whose user turned the unlock on, then logged out: a
  /// registered key in the key store and the record in the settings. Set
  /// up through the store, not the page, in real time (the fake clock of a
  /// widget test does not run the session's close).
  Future<void> enroll(WidgetTester t) => t.runAsync(_enroll);

  Future<void> _enroll() async {
    await fill();
    await store.dispatchAndWait(LoadDeviceAction());
    await store.dispatchAndWait(LogInAction());
    await store.dispatchAndWait(OfferDeviceAction());
    if (store.state.device.deviceId == null) {
      await store.dispatchAndWait(EnableDeviceAction(reason: 'setup'));
    }
    expect(store.state.device.deviceId, isNotNull, reason: 'enrolled');
    await store.dispatchAndWait(LogOutAction());
    keys.reasons.clear();
  }

  /// Logged in through the store (the lock and the step-up need a session).
  Future<void> logIn(WidgetTester t) => t.runAsync(_logIn);

  Future<void> _logIn() async {
    await fill();
    final status = await store.dispatchAndWait(LogInAction());
    expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
  }

  /// Lays [change] into the store, as the test needs it.
  void put(AppState Function(AppState) change) =>
      store.dispatchSync(_Put(change));

  /// The log-in page in [locale], on a 1440 × 1000 window.
  Future<void> pumpLogIn(
    WidgetTester t, {
    Locale locale = const Locale('en'),
  }) => _pump(t, const LogInPageConnector(), locale: locale);

  /// The idle lock over a plain child, as the Studio shell has it.
  Future<void> pumpLock(
    WidgetTester t, {
    Locale locale = const Locale('en'),
  }) => _pump(
    t,
    const Scaffold(
      body: LockOverlayConnector(child: Center(child: Text('the shell'))),
    ),
    locale: locale,
  );

  /// The step-up over a plain page, as the app's builder has it.
  Future<void> pumpStepUp(
    WidgetTester t, {
    Locale locale = const Locale('en'),
  }) => _pump(
    t,
    const Scaffold(
      body: Stack(
        children: [
          Center(child: Text('a page')),
          Positioned.fill(child: StepUpDialogConnector()),
        ],
      ),
    ),
    locale: locale,
  );

  Future<void> _pump(
    WidgetTester t,
    Widget home, {
    required Locale locale,
  }) async {
    await S.load(locale);
    t.view.physicalSize = const Size(1440, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: darkTheme(),
          locale: locale,
          supportedLocales: S.delegate.supportedLocales,
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: home,
        ),
      ),
    );
    await settle(t);
  }

  /// Lets the fakes answer and the page follow, without waiting for the
  /// hero's loops (they never settle).
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets the welcome's preload run out (`OpenTreeAction` waits at most
  /// 5 s on the fake broker, which never lists the tree).
  Future<void> settleWelcome(WidgetTester t) async {
    for (var i = 0; i < 70; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Takes the page off the screen.
  Future<void> leave(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  /// Every word on the log-in page, in the order of the tree.
  List<String> logInWords(WidgetTester t) => _words(t, LogInPage);

  /// Every word on the lock (the card and the shell under it).
  List<String> lockWords(WidgetTester t) => _words(t, LockOverlay);

  /// Every word of the step-up dialog.
  List<String> stepUpWords(WidgetTester t) => _words(t, StepUpDialog);

  /// The words of [root] in the order of the tree, then what each of its
  /// fields holds (`•••` for one that hides what it holds).
  List<String> _words(WidgetTester t, Type root) => [
    for (final w in t.widgetList<RichText>(
      find.descendant(of: find.byType(root), matching: find.byType(RichText)),
    ))
      w.text.toPlainText(),
    for (final e in t.widgetList<EditableText>(
      find.descendant(
        of: find.byType(root),
        matching: find.byType(EditableText),
      ),
    ))
      'field: ${e.obscureText ? '•••' : e.controller.text}',
  ];
}

/// Lays a state in, as the test needs it.
class _Put extends ReduxAction<AppState> {
  _Put(this.change);

  final AppState Function(AppState) change;

  @override
  AppState reduce() => change(state);
}
