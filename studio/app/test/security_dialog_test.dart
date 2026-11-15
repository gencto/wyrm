// A long word of the dialog is written as adjacent strings: one item.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:app/connectors/security_dialog_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/remove_device_action.dart';
import 'package:business/redux/device/actions/retrieve_devices_action.dart';
import 'package:business/redux/device/actions/set_device_unlock_action.dart';
import 'package:business/redux/device/actions/set_lock_after_action.dart';
import 'package:device_key/testing.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/device_policy_info.dart';
import 'package:models/key_kind.dart';
import 'package:storage/storage.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show DevicePlatform, GatewayDevice, GatewayDeviceState;

import 'support/assistant_app.dart';

/// Account › Security as the store makes it: every word on the dialog for a
/// state with each kind of device row. Written before the dialog moved its
/// words into `ui` (studio-rules §5), so it holds the words the connector
/// gave then.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  AppState stateAt(DateTime now, {bool confirm = true, String? error}) {
    final a = AppState.initial();
    return a.copyWith(
      site: a.site.copyWith(name: 'plant'),
      login: a.login.copyWith(user: 'olena'),
      device: a.device.copyWith(
        available: true,
        kind: KeyKind.touchId,
        keyId: 'k1',
        deviceId: 'd1',
        added: s(DateTime(2026, 11, 3, 10)),
        lockAfter: 15,
        needPassword: error != null,
        securityError: error,
        policy: DevicePolicyInfo(
          enabled: true,
          stepUp: confirm ? 'config' : 'none',
        ),
        devices: IList([
          GatewayDevice(
            id: 'd1',
            name: 'MacBook Pro · Studio',
            platform: DevicePlatform.macos,
            added: s(DateTime(2026, 11, 3, 10)),
            lastUsed: s(now.subtract(const Duration(seconds: 20))),
            thisSession: true,
          ),
          GatewayDevice(
            id: 'd2',
            name: 'iPhone 15 · Studio',
            platform: DevicePlatform.ios,
            added: s(DateTime(2026, 10, 28, 10)),
            lastUsed: s(now.subtract(const Duration(days: 2, hours: 1))),
          ),
          GatewayDevice(
            id: 'd3',
            name: 'ENG-LAPTOP-07 · Studio',
            platform: DevicePlatform.windows,
            lastUsed: s(now.subtract(const Duration(days: 26))),
            passwordDueAt: s(now.add(const Duration(days: 3, hours: 12))),
          ),
          const GatewayDevice(
            id: 'd4',
            name: 'Pixel 8 · Studio',
            platform: DevicePlatform.android,
            state: GatewayDeviceState.removed,
            removedBy: 'user:ivan',
          ),
          const GatewayDevice(
            id: 'd5',
            name: 'Old box',
            platform: null,
            state: GatewayDeviceState.signedOut,
          ),
        ]),
      ),
    );
  }

  Future<List<String>> words(
    WidgetTester t,
    AppState state, {
    List<ActionObserver<AppState>> seen = const [],
  }) async {
    final store = Store<AppState>(
      initialState: state,
      actionObservers: seen,
      dependencies: (s) => AppDependencies(
        s,
        InMemoryKeyValueStorage(),
        login: FakeLogin(),
        deviceKey: FakeDeviceKey(availability: DeviceKeyAvailability.none),
      ),
    );
    await t.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: darkTheme(),
          localizationsDelegates: const [S.delegate],
          home: const Scaffold(
            body: SingleChildScrollView(child: SecurityDialogConnector()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return [
      for (final w in t.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
    ];
  }

  testWidgets('every word of the dialog, as the store gives them', (t) async {
    t.view.physicalSize = const Size(1400, 2400);
    addTearDown(t.view.reset);
    await S.load(const Locale('en'));
    final got = await words(t, stateAt(DateTime.now()));
    expect(got, _expected);
  }, variant: mac);

  testWidgets('without the step-up and with a wrong password', (t) async {
    t.view.physicalSize = const Size(1400, 2400);
    addTearDown(t.view.reset);
    await S.load(const Locale('en'));
    final got = await words(
      t,
      stateAt(DateTime.now(), confirm: false, error: 'bad_password'),
    );
    expect(got, _expectedNoConfirm);
  }, variant: mac);

  testWidgets('each control starts one action, and the prompt has its words', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 2400);
    addTearDown(t.view.reset);
    await S.load(const Locale('en'));
    final seen = _Seen();
    await words(t, stateAt(DateTime.now()), seen: [seen]);
    expect(seen.started.whereType<RetrieveDevicesAction>(), hasLength(1));

    seen.started.clear();
    await t.tap(find.text('Remove').first);
    await t.pump();
    expect(
      seen.started.whereType<RemoveDeviceAction>().map((a) => a.id),
      ['d2'],
    );

    seen.started.clear();
    await t.tap(find.text('15 min'));
    await t.pumpAndSettle();
    expect(
      [
        for (final w in t.widgetList<PopupMenuItem<int>>(
          find.byType(PopupMenuItem<int>),
        ))
          w.value,
      ],
      [0, 5, 15, 30],
    );
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    await t.tap(find.text('5 min'));
    await t.pumpAndSettle();
    expect(
      seen.started.whereType<SetLockAfterAction>().map((a) => a.minutes),
      [5],
    );
  }, variant: mac);

  testWidgets('the switch turns the unlock off with the prompt', (t) async {
    t.view.physicalSize = const Size(1400, 2400);
    addTearDown(t.view.reset);
    await S.load(const Locale('en'));
    final seen = _Seen();
    await words(t, stateAt(DateTime.now()), seen: [seen]);
    seen.started.clear();
    // the first switch is the unlock; the second, the step-up, is locked
    await t.tap(
      find
          .byWidgetPredicate(
            (w) => w is Semantics && (w.properties.toggled ?? false),
          )
          .first,
    );
    await t.pump();
    final a = seen.started.whereType<SetDeviceUnlockAction>().single;
    expect(a.on, isFalse);
    expect(
      a.reason,
      S.current.unlockEnablePrompt('plant', 'olena'),
    );
  }, variant: mac);
}

/// The actions the dialog starts, in order.
class _Seen implements ActionObserver<AppState> {
  final started = <ReduxAction<AppState>>[];

  @override
  void observe(
    ReduxAction<AppState> action,
    int dispatchCount, {
    required bool ini,
  }) {
    if (ini) {
      started.add(action);
    }
  }
}

const _expected = <String>[
  'Security',
  'olena · plant',
  '×',
  'ON THIS MAC',
  'Unlock with Touch ID',
  'A key in this Mac’s Secure Enclave, added 3 Nov. Off removes the '
      'key here and this Mac from your devices.',
  'Lock Studio after',
  'Hides the tree and values; the session and Review and apply are '
      'kept. plant allows at most 30 min.',
  '15 min',
  'Confirm before config changes',
  'Set by plant (gateway.devices.step_up: config); you cannot turn it '
      'off here.',
  'YOUR DEVICES ON PLANT',
  'mac',
  'MacBook Pro · Studio this device',
  'Touch ID · used now · added 3 Nov',
  'Turn off',
  'iOS',
  'iPhone 15 · Studio',
  'Face ID · 2 d ago · added 28 Oct',
  'Remove',
  'win',
  'ENG-LAPTOP-07 · Studio password due in 4 days',
  'Windows Hello · 26 d ago',
  'Remove',
  'and',
  'Pixel 8 · Studio removed by ivan',
  'fingerprint · removed · signs in with the password only',
  'Forget',
  '?',
  'Old box signed out',
  'biometrics',
  'Remove',
  'plant’s policy: devices on · up to 5 · password every 30 days · '
      'confirm config changes. An administrator sees and removes devices '
      'in Access › Users.',
  'Sign out everywhere',
];

const _expectedNoConfirm = <String>[
  'Security',
  'olena · plant',
  '×',
  'ON THIS MAC',
  'Unlock with Touch ID',
  'A key in this Mac’s Secure Enclave, added 3 Nov. Off removes the '
      'key here and this Mac from your devices.',
  'plant asks for your password before a new key.',
  'The password is wrong.',
  'Turn on',
  'Lock Studio after',
  'Hides the tree and values; the session and Review and apply are '
      'kept. plant allows at most 30 min.',
  '15 min',
  'Confirm before config changes',
  'plant does not ask for it (gateway.devices.step_up: none); only the '
      'gateway can turn it on.',
  'YOUR DEVICES ON PLANT',
  'mac',
  'MacBook Pro · Studio this device',
  'Touch ID · used now · added 3 Nov',
  'Turn off',
  'iOS',
  'iPhone 15 · Studio',
  'Face ID · 2 d ago · added 28 Oct',
  'Remove',
  'win',
  'ENG-LAPTOP-07 · Studio password due in 4 days',
  'Windows Hello · 26 d ago',
  'Remove',
  'and',
  'Pixel 8 · Studio removed by ivan',
  'fingerprint · removed · signs in with the password only',
  'Forget',
  '?',
  'Old box signed out',
  'biometrics',
  'Remove',
  'plant’s policy: devices on · up to 5 · password every 30 days. An '
      'administrator sees and removes devices in Access › Users.',
  'Sign out everywhere',
];
