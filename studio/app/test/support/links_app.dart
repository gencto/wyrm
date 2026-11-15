import 'package:app/common/app_store.dart';
import 'package:app/connectors/links_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_wyrm.dart';
import 'link_install_app.dart' show FakeFilePicker;

export '../../../business/test/support/fake_wyrm.dart';

/// The site of every Links test.
const plant = 'wy/plant';

/// `wy/plant/sys`.
const sys = '$plant/sys';

/// Lets a row that overflows in the test font pass for this test: the
/// update sheet's footer is wider in the square test glyphs than in the
/// app's font (the goldens draw it in the real one). Words, not layout,
/// are what these tests read.
void ignoreOverflow() {
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (!d.exceptionAsString().contains('overflowed')) {
      old?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = old);
}

/// What a fixture's broker holds (ADR 0011, 0013, 0015, 0048).
final class LinksFixture {
  const LinksFixture({
    this.update = UpdateShown.none,
    this.points = true,
    this.backups = true,
  });

  /// What `sys/packages/bacnet/last_update` says.
  final UpdateShown update;

  /// `bacnet` has a restore point.
  final bool points;

  /// `sys/backups` exists (ADR 0048).
  final bool backups;
}

/// The last update of `bacnet` in a fixture.
enum UpdateShown { none, checking, checkingKept, ok, rolledBack, failed, gone }

/// Links over a fake gateway: the site `plant` with four links (a built-in
/// driver, an official package with an update, a custom WASM package and
/// an external link), two packages, three quarantine entries and the
/// admission options, as the connector reads them when it is shown.
class LinksApp {
  LinksApp({this.fixture = const LinksFixture(), bool config = true})
    : login = FakeLogin(
        session: FakeSession(
          who: identityOf(
            subject: 'user:olena',
            site: 'plant',
            roles: const ['admin'],
            max: 'config',
            grants: [
              ('$plant/**', config ? 'config' : 'read'),
            ],
          ),
        ),
      ) {
    store = fakeStore(login: login);
    _broker();
  }

  final LinksFixture fixture;
  final FakeLogin login;
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;

  /// The system's file dialog.
  final picker = FakeFilePicker();

  /// When the quarantine entry `field-gw` was first seen: five minutes
  /// before the test.
  final DateTime seen = DateTime.now().toUtc().subtract(
    const Duration(minutes: 5),
  );

  void _broker() {
    NodeMeta link(Map<String, String> attr, {String? name}) => NodeMeta(
      display: name,
      attr: {for (final e in attr.entries) e.key: VStr(e.value)},
    );
    api
      ..children_['$sys/links'] = [
        for (final id in ['modbus', 'bacnet', 'telegram', 'field-cam'])
          Child(id, NodeMeta()),
      ]
      ..metas['$sys/links'] = NodeMeta(
        attr: {'updates_available': const VInt(1)},
      )
      ..metas['$sys/links/modbus'] = link({
        'driver': 'modbus',
        'mode': 'embedded',
        'origin': 'config',
      })
      ..metas['$sys/links/bacnet'] = link({
        'driver': 'pkg:bacnet',
        'mode': 'process',
        'package': 'bacnet',
        'origin': 'runtime',
      })
      ..metas['$sys/links/telegram'] = link({
        'driver': 'pkg:telegram',
        'mode': 'embedded',
        'package': 'telegram',
        'origin': 'runtime',
      })
      ..metas['$sys/links/field-cam'] = link({
        'driver': 'external',
        'mode': 'external',
        'device': '10.0.4.17',
        'cn': 'link:field-cam',
        'origin': 'runtime',
      }, name: 'Gate camera')
      ..initial['$sys/version'] = [
        const ValSample('$sys/version', Sample(VStr('0.1.0'), t: 0)),
      ]
      ..children_['$sys/packages'] = [
        Child('bacnet', NodeMeta()),
        Child('telegram', NodeMeta()),
      ]
      ..metas['$sys/packages/bacnet'] = link({
        'version': '0.2.0',
        'kind': 'process',
        'source': 'repository official',
        'sha256':
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      })
      ..metas['$sys/packages/telegram'] = link({
        'version': '1.4.2',
        'kind': 'wasm',
        'source': 'zip upload',
      })
      ..children_['$sys/quarantine'] = [
        Child('field-gw', NodeMeta()),
        Child('line2', NodeMeta()),
        Child('old', NodeMeta()),
      ]
      ..metas['$sys/quarantine/field-gw'] = NodeMeta(
        display: 'link:field-gw',
        attr: {
          'kind': const VStr('link'),
          'from': const VStr('10.0.4.20:51234'),
          'first_seen': VStr(seen.toIso8601String()),
          'key': const VStr('ed25519:AAAAC3NzaC1lZDI1NTE5AAAAIB'),
        },
        actions: {
          'approve': ActionMeta(
            level: Perm.config,
            params: {
              'name': ParamMeta(ty: TypeCode.string, required: true),
              'role': ParamMeta(
                ty: TypeCode.enum_,
                enumValues: const ['write', 'read'],
              ),
            },
          ),
        },
      )
      ..metas['$sys/quarantine/line2'] = NodeMeta(
        display: 'broker:line2',
        attr: {
          'kind': const VStr('broker'),
          'via': const VArray([VStr('line3')]),
        },
      )
      ..metas['$sys/quarantine/old'] = NodeMeta(
        display: 'link:old',
        attr: {'kind': const VStr('link'), 'held': const VBool(true)},
      );
    for (final id in ['modbus', 'bacnet', 'telegram', 'field-cam']) {
      api
        ..invokes['$sys/links/$id ▸ start'] = const [VNull()]
        ..invokes['$sys/links/$id ▸ stop'] = const [VNull()]
        ..invokes['$sys/links/$id ▸ remove'] = const [VNull()];
    }
    api
      ..invokes['$sys/links ▸ deauthorize'] = const [VNull()]
      ..invokes['$sys/quarantine/field-gw ▸ approve'] = const [VNull()]
      ..invokes['$sys/quarantine/field-gw ▸ reject'] = const [VNull()]
      ..invokes['$sys/packages/bacnet ▸ update'] = [
        Value.from({'success': true, 'message': 'updated'}),
      ]
      ..invokes['$sys/links ▸ install_zip'] = [
        Value.from({'success': true, 'message': 'telegram updated'}),
      ]
      ..invokes['$sys/packages/bacnet ▸ rollback'] = [
        Value.from({'success': true, 'message': 'rolled back'}),
      ];
    if (fixture.backups) {
      api.metas['$sys/backups'] = NodeMeta(
        attr: {
          'sections': const VArray([VStr('control'), VStr('links')]),
          'keep_days': const VInt(7),
        },
      );
      api.children_['$sys/backups'] = const [];
    } else {
      api.errors['$sys/backups'] = WyrmException.of(
        Status.notFound,
        'no sys/backups',
      );
    }
  }

  /// `last_update` of `bacnet` for [UpdateShown].
  Map<String, Object?> get _lastUpdate => switch (fixture.update) {
    UpdateShown.none => const {},
    UpdateShown.checking || UpdateShown.checkingKept => const {
      'from': '0.2.0',
      'to': '0.3.0',
      'at': 1762912800,
      'result': 'checking',
      'links': ['bacnet'],
      'restore_point': true,
    },
    UpdateShown.ok => const {
      'from': '0.2.0',
      'to': '0.3.0',
      'at': 1762912800,
      'result': 'ok',
      'kept': 41,
      'new': 2,
      'gone': 0,
      'new_keys': ['bacnet/dev1/alarm', 'bacnet/dev1/mode'],
      'links': ['bacnet'],
      'restore_point': true,
    },
    UpdateShown.rolledBack => const {
      'from': '0.2.0',
      'to': '0.3.0',
      'at': 1762912800,
      'result': 'rolled_back',
      'kept': 41,
      'reason': 'bacnet did not come back within 60 s',
      'links': ['bacnet'],
    },
    UpdateShown.failed => const {
      'from': '0.2.0',
      'to': '0.3.0',
      'at': 1762912800,
      'result': 'failed',
      'reason': '',
      'links': ['bacnet'],
    },
    UpdateShown.gone => const {
      'from': '0.2.0',
      'to': '0.3.0',
      'at': 1762912800,
      'result': 'ok',
      'kept': 39,
      'new': 0,
      'gone': 2,
      'gone_keys': ['bacnet/dev1/old', 'bacnet/dev2/old'],
      'reason': '2 nodes are no longer declared',
      'links': ['bacnet'],
    },
  };

  /// The live values the screen watches.
  Map<String, Object?> get _values => {
    '$sys/links/modbus/state': 2,
    '$sys/links/bacnet/state': 'failed',
    '$sys/links/telegram/state': 1,
    '$sys/links/field-cam/state': 'stopped',
    '$sys/enable_quarantine': true,
    '$sys/allow_all_links': false,
    '$sys/packages/bacnet/version': '0.2.0',
    '$sys/packages/bacnet/latest': '0.3.0',
    '$sys/packages/bacnet/update_available': true,
    '$sys/packages/bacnet/changes_state': false,
    '$sys/packages/bacnet/state': 1,
    '$sys/packages/bacnet/previous':
        fixture.update == UpdateShown.none ||
            fixture.update == UpdateShown.checking
        ? const <String, Object?>{}
        : const {'version': '0.2.0', 'keep_until': 1763517600},
    '$sys/packages/bacnet/last_update': _lastUpdate,
    '$sys/packages/telegram/version': '1.4.2',
    '$sys/packages/telegram/latest': '',
    '$sys/packages/telegram/update_available': false,
    '$sys/packages/telegram/last_update': const <String, Object?>{},
    '$sys/links/bacnet/restore_points': fixture.points
        ? const [
            {'at': 1762909200, 'version': '0.2.0', 'size': 48213},
          ]
        : const <Object?>[],
  };

  /// The values a read of one key finds (the broker's `~val` storage).
  void _stored() {
    for (final e in _values.entries) {
      api.initial[e.key] = [
        ValSample(e.key, Sample(Value.from(e.value), t: 0)),
      ];
    }
  }

  /// Lays the live values in, as the broker sends them.
  void values() {
    final now = DateTime.utc(2026, 11, 12, 2, 2);
    store.dispatchSync(
      SetLiveValuesAction({
        for (final e in _values.entries)
          e.key: LiveValue(time: now, value: e.value),
      }),
    );
  }

  Future<void> _prepare(WidgetTester tester) async {
    _stored();
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ignoreOverflow();
    final was = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = was);
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
    });
  }

  /// Logs in and shows Links in [locale], with the broker's values.
  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await _prepare(tester);
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
            home: const Scaffold(body: LinksPageConnector()),
          ),
        ),
      ),
    );
    await settle(tester);
    values();
    await settle(tester);
  }

  /// Lets the fake broker's answers arrive and the screen follow them.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps the text [label] on Links (a tab, a row, an action, a button).
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(LinksPageConnector),
            matching: find.text(label),
          )
          .first,
    );
    await settle(tester);
  }

  /// Taps [label] in a dialog over Links.
  Future<void> answer(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text(label)).last,
    );
    await settle(tester);
  }

  /// Every word on Links, in the order of the tree.
  List<String> words(WidgetTester tester) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(LinksPageConnector),
        matching: find.byType(RichText),
      ),
    ))
      w.text.toPlainText(),
  ];

  /// Every word of the dialog on screen.
  List<String> dialogWords(WidgetTester tester) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(RichText),
      ),
    ))
      w.text.toPlainText(),
  ];

  /// The calls of [action] (an invoke's name, or `children`, `meta`) made
  /// so far.
  List<Call> calls(String action) => [
    for (final c in api.calls)
      if (c.action == action || (c.action == null && c.op == action)) c,
  ];

  /// Takes Links off the screen (it unwatches).
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }
}
