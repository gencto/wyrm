import 'package:app/connectors/explorer_page_connector.dart';
import 'package:app/connectors/toast_stack_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/live/actions/set_read_failed_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/add_nodes_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:device_key/testing.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/panel_slot.dart';
import 'package:models/quality.dart' as m;
import 'package:storage/storage.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_wyrm.dart';

export '../../../business/test/support/fake_wyrm.dart';

/// Explorer over a fake gateway: the site `central` with the modbus link
/// `modbus`, its connection `tcp`, the device `plc1` and its points, a
/// flow and a storage folder, as the tree and the live values hand them.
///
/// Times are local wall times, so the words they make (`12:00:03`) are the
/// same on every machine.
class ExplorerApp {
  ExplorerApp({String level = 'config', this.connected = true})
    : login = FakeLogin(
        session: FakeSession(
          who: identityOf(
            subject: 'olena',
            site: 'central',
            roles: const ['engineer'],
            max: 'config',
            grants: [('wy/central/**', level)],
          ),
        ),
      ) {
    store = Store<AppState>(
      initialState: AppState.initial(),
      actionObservers: [_Seen(started)],
      globalErrorObserver: (_) => _Errors(errors),
      dependencies: (s) => AppDependencies(
        s,
        InMemoryKeyValueStorage(),
        login: login,
        deviceKey: FakeDeviceKey(availability: DeviceKeyAvailability.none),
        clock: () => now,
      ),
    );
    _broker();
  }

  static const root = 'wy/central';
  static const link = '$root/downstream/modbus';
  static const conn = '$link/tcp';
  static const dev = '$conn/plc1';
  static const temp = '$dev/temp';
  static const mode = '$dev/mode';
  static const alarm = '$dev/alarm';
  static const flow = '$root/dataflows/tank';
  static const folder = '$root/storage/notes';

  /// The time now, as the store's clock gives it: the newest history row
  /// (11:59:30, local), so a history read ends there on every machine and
  /// in every zone.
  static final now = DateTime(2026, 11, 15, 11, 59, 30);

  /// When the points were last read: 12:00:03, local.
  static final at = DateTime(2026, 11, 15, 12, 0, 3);

  final FakeLogin login;
  final bool connected;

  /// Every action started, in order (navigation is checked by its action:
  /// no router runs here).
  final started = <ReduxAction<AppState>>[];

  /// The errors the store caught (a navigation with no router mounted).
  final errors = <Object>[];
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;

  /// The calls of [op] (`invoke`, `history`, `meta`) made so far.
  List<Call> calls(String op) => [
    for (final c in api.calls)
      if (c.op == op) c,
  ];

  void _broker() {
    ParamMeta p({TypeCode? ty, List<String>? choices, Value? def}) =>
        ParamMeta(ty: ty, enumValues: choices, defaultValue: def);
    api
      ..children_['$root/sys/links'] = [Child('modbus', NodeMeta())]
      ..metas['$root/sys/links/modbus'] = NodeMeta(
        attr: {'driver': const VStr('modbus'), 'mode': const VStr('process')},
      )
      ..metas[link] = NodeMeta(
        is_: const TText('wy:link'),
        attr: {'driver': const VStr('modbus')},
      )
      ..metas[conn] = NodeMeta(
        is_: const TText('modbus:conn'),
        cfg: {'host': const VStr('127.0.0.1'), 'port': const VInt(5020)},
        actions: {
          'add_device': ActionMeta(
            level: Perm.config,
            params: {
              'name': p(),
              'unit': p(ty: TypeCode.number),
            },
          ),
          'restart': ActionMeta(level: Perm.write, group: 'Run'),
        },
      )
      ..metas[dev] = NodeMeta(
        is_: const TText('modbus:device'),
        display: 'Boiler PLC',
        cfg: {'unit': const VInt(1)},
        actions: {
          'add_point': ActionMeta(
            level: Perm.config,
            params: {
              'name': p(),
              'table': p(choices: ['holding', 'input', 'coil', 'discrete']),
              'addr': p(ty: TypeCode.number),
            },
          ),
          'import_dsa': ActionMeta(level: Perm.config, params: {'file': p()}),
          'ping': ActionMeta(level: Perm.write),
          'read_registers': ActionMeta(
            level: Perm.write,
            params: {'start': p(ty: TypeCode.number)},
            result: const ResultStream(),
          ),
          'remove_device': ActionMeta(level: Perm.config),
        },
      )
      ..invokes['$dev ▸ ping'] = [
        Value.from({'success': true, 'rtt_ms': 4}),
      ]
      ..invokes['$dev ▸ read_registers'] = [
        Value.from([
          {'addr': 10, 'value': 215},
          {'addr': 11, 'value': 0},
        ]),
      ]
      ..metas[temp] = NodeMeta(
        ty: TypeCode.number,
        unit: const TText('°C'),
        writable: Writable.write,
        display: 'Boiler temperature',
        cfg: {
          'table': const VStr('holding'),
          'addr': const VInt(10),
          'dtype': const VStr('f32_wswap'),
          'poll_s': const VFloat(1),
        },
        actions: {
          'edit': ActionMeta(
            level: Perm.config,
            params: {
              'table': p(
                choices: ['holding', 'input', 'coil', 'discrete'],
                def: const VStr('holding'),
              ),
              'addr': p(ty: TypeCode.number, def: const VInt(10)),
              'dtype': p(
                choices: ['u16', 'f32', 'f32_wswap'],
                def: const VStr('f32_wswap'),
              ),
              'unit': p(def: const VStr('°C')),
              'scale': p(ty: TypeCode.number, def: const VFloat(1)),
              'poll_s': p(ty: TypeCode.number, def: const VFloat(1)),
              'writable': p(ty: TypeCode.bool_, def: const VBool(true)),
            },
          ),
          'remove': ActionMeta(level: Perm.config),
        },
      )
      ..metas[mode] = NodeMeta(
        ty: TypeCode.enum_,
        enumValues: const ['auto', 'manual'],
        cfg: {'table': const VStr('coil'), 'addr': const VInt(3)},
        actions: {
          'edit': ActionMeta(
            level: Perm.config,
            params: {'poll_s': p(ty: TypeCode.number, def: const VFloat(5))},
          ),
          'remove': ActionMeta(level: Perm.config),
        },
      )
      ..metas[alarm] = NodeMeta(
        ty: TypeCode.bool_,
        cfg: {'address': const VStr('DB1.DBX0.0')},
      )
      ..metas[flow] = NodeMeta(
        is_: const TText('wy:flow'),
        display: 'Tank level from two sensors',
        actions: {
          'deploy': ActionMeta(level: Perm.config, params: {'def': p()}),
          'start': ActionMeta(level: Perm.write),
        },
      )
      ..metas[folder] = NodeMeta(attr: {'owner': const VStr('ops')})
      ..histories[temp] = [
        HistRow(
          DateTime(2026, 11, 15, 11, 59).microsecondsSinceEpoch,
          const VFloat(21),
          Quality.good,
        ),
        HistRow(
          DateTime(2026, 11, 15, 11, 59, 30).microsecondsSinceEpoch,
          const VFloat(21.5),
          Quality.uncertain,
        ),
      ]
      ..invokes['$root/sys/audit ▸ tail'] = [
        Value.from([
          {
            't': DateTime(2026, 11, 15, 11, 58).microsecondsSinceEpoch,
            'op': 'set',
            'key': temp,
            'sub': 'user:olena',
            'status': 0,
          },
          {
            't': DateTime(2026, 11, 15, 11, 57).microsecondsSinceEpoch,
            'op': 'invoke',
            'key': dev,
            'sub': 'user:ivan',
            'status': 3,
          },
          {
            't': DateTime(2026, 11, 15, 11, 56).microsecondsSinceEpoch,
            'op': 'set',
            'key': '$root/downstream/other/x',
            'sub': 'user:ivan',
            'status': 0,
          },
        ]),
      ];
  }

  /// The tree as the live lists hand it.
  static IList<NodeInfo> get tree => [
    const NodeInfo(
      key: link,
      name: 'modbus',
      profile: 'wy:link',
      hasChildren: true,
    ),
    const NodeInfo(
      key: conn,
      name: 'tcp',
      profile: 'modbus:conn',
      hasChildren: true,
    ),
    const NodeInfo(
      key: '$conn/status',
      name: 'status',
      type: TypeCode.enum_,
      choices: IListConst(['connected', 'connecting', 'failed']),
    ),
    const NodeInfo(
      key: '$conn/requests',
      name: 'requests',
      type: TypeCode.number,
    ),
    const NodeInfo(
      key: '$conn/mirror',
      name: 'mirror',
      type: TypeCode.number,
      unit: 'bar',
      display: 'Mirrored pressure',
      writable: Perm.write,
    ),
    const NodeInfo(
      key: dev,
      name: 'plc1',
      display: 'Boiler PLC',
      profile: 'modbus:device',
      hasChildren: true,
    ),
    const NodeInfo(
      key: temp,
      name: 'temp',
      display: 'Boiler temperature',
      type: TypeCode.number,
      unit: '°C',
      writable: Perm.write,
      hasHistory: true,
    ),
    const NodeInfo(
      key: mode,
      name: 'mode',
      type: TypeCode.enum_,
      choices: IListConst(['auto', 'manual']),
    ),
    const NodeInfo(key: alarm, name: 'alarm', type: TypeCode.bool_),
    const NodeInfo(key: '$dev/status', name: 'status', type: TypeCode.string),
    const NodeInfo(
      key: '$root/downstream/opc',
      name: 'opc',
      profile: 'wy:link',
      hasChildren: true,
    ),
    const NodeInfo(key: flow, name: 'tank', profile: 'wy:flow'),
    const NodeInfo(key: folder, name: 'notes', hasChildren: true),
  ].lock;

  /// The live values: the link connected, the connection's status, the
  /// points (the alarm's read failed), the flow's `~val`.
  Map<String, LiveValue?> get values => {
    '$root/sys/links/modbus/state': LiveValue(time: at, value: 2),
    '$root/sys/links/opc/state': LiveValue(time: at, value: 5),
    '$conn/status': LiveValue(time: at, value: 0),
    '$conn/requests': LiveValue(time: at, value: 120),
    '$conn/mirror': LiveValue(time: at, value: 1.5),
    temp: LiveValue(time: at, value: 21.5),
    mode: LiveValue(time: at, value: 1, quality: m.Quality.uncertain),
    '$dev/status': LiveValue(time: at, value: 'connected'),
    flow: LiveValue(
      time: at,
      value: {
        'state': 0,
        'version': 3,
        'deployed_by': 'user:olena',
        'since': DateTime(2026, 11, 14, 9, 30, 5).microsecondsSinceEpoch,
      },
    ),
  };

  /// Logs in, puts the tree and the values in, and shows Explorer.
  /// With [toasts], the toast stack is over the page (the toasts' words).
  Future<void> pump(WidgetTester tester, {bool toasts = false}) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
    });
    store
      ..dispatchSync(AddNodesAction(tree))
      ..dispatchSync(ToggleNodeAction('$root/downstream', open: true))
      ..dispatchSync(ToggleNodeAction(link, open: true))
      ..dispatchSync(ToggleNodeAction(conn, open: true))
      ..dispatchSync(ToggleNodeAction('$root/dataflows', open: true))
      ..dispatchSync(SetLiveValuesAction(values))
      ..dispatchSync(SetReadFailedAction(alarm, 'timeout'))
      // wide panels: a selected link's chip, dot and menu fit beside its
      // name, an enum's value and its quality fit on one line
      ..dispatchSync(SetPanelWidthAction(PanelSlot.explorerTree, 320))
      ..dispatchSync(SetPanelWidthAction(PanelSlot.explorerInspector, 400));
    if (!connected) {
      store.dispatchSync(_Offline());
    }
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: darkTheme(),
          localizationsDelegates: const [S.delegate],
          home: Scaffold(
            body: toasts
                ? const Stack(
                    children: [
                      Positioned.fill(child: ExplorerPageConnector()),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: ToastStackConnector(),
                      ),
                    ],
                  )
                : const ExplorerPageConnector(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets the fake broker's answers arrive and the screen follow them.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      // a read may wait for the broker's version (2 s) before it goes on
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// What the clipboard was given, in order.
  static List<String> watchClipboard(WidgetTester tester) {
    final out = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          out.add('${args['text']}');
        }
        return null;
      },
    );
    return out;
  }
}

class _Seen implements ActionObserver<AppState> {
  _Seen(this.started);

  final List<ReduxAction<AppState>> started;

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

class _Errors extends GlobalErrorObserver<AppState> {
  _Errors(this.errors);

  final List<Object> errors;

  @override
  Object? observe() {
    errors.add(error);
    return null;
  }
}

/// The site goes offline (the gateway's socket closed).
class _Offline extends ReduxAction<AppState> {
  @override
  AppState reduce() => state.copyWith.site(connected: false);
}
