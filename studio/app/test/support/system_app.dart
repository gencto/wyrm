import 'dart:async';

import 'package:app/common/app_store.dart';
import 'package:app/connectors/system_page_connector.dart';
import 'package:app/connectors/toast_stack_connector.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/live_value.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/traffic_sample.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/system_page.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_wyrm.dart';

export '../../../business/test/support/fake_wyrm.dart';

/// The site of every System test.
const plant = 'wy/plant';

/// `wy/plant/sys`.
const sys = '$plant/sys';

/// The tabs of System, by the label the user taps.
enum SysTab {
  overview,
  availability,
  log,
  maintenance;

  String get label => switch (this) {
    overview => S.current.sysTabOverview,
    availability => S.current.sysTabAvailability,
    log => S.current.sysTabLog,
    maintenance => S.current.sysTabMaintenance,
  };
}

/// The standby of a fixture.
enum Standby { following, lag, forks, both, none }

/// What a fixture's broker holds (ADR 0036, 0048; specs/system.md).
final class SysFixture {
  const SysFixture({
    this.connected = true,
    this.values = true,
    this.standby = Standby.following,
    this.lease = 12,
    this.stale = 1,
    this.profilesListed = true,
    this.backups = true,
    this.aclSeen = 18000,
    this.samples = false,
    this.level = 2,
  });

  /// The gateway socket is up.
  final bool connected;

  /// The broker has published its `sys` values.
  final bool values;
  final Standby standby;

  /// `arbiter_lease_s`; 0 for no arbiter.
  final int lease;

  /// How many runtime external links are not connected (`clear_conns`).
  final int stale;

  /// `pub` is listed; else `not_found` (wyrmd 0.1.0).
  final bool profilesListed;

  /// `sys/backups` exists (ADR 0048).
  final bool backups;

  /// What `acl_denied` was when System was last left.
  final int? aclSeen;

  /// The traffic ring holds samples.
  final bool samples;

  /// `sys/log_level` as its code.
  final Object level;
}

/// System over a fake gateway: the site `plant` with its `sys` values,
/// links, quarantine, peers, profiles, backups and log, as the connector
/// reads them when the tab is shown.
class SystemApp {
  SystemApp({this.fixture = const SysFixture(), bool config = true})
    : login = FakeLogin(
        session: FakeSession(
          who: WhoAmI(
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

  final SysFixture fixture;
  final FakeLogin login;
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;

  /// What the clipboard was given last.
  String? clipboard;

  /// The `get_log` arguments of every read, in order.
  final logReads = <Value?>[];

  void _broker() {
    final f = fixture;
    // the descriptions and units of the `sys` values (RetrieveSysAboutAction)
    api
      ..children_[sys] = [
        Child('cpu', NodeMeta(ty: TypeCode.number)),
        Child('links_connected', NodeMeta(ty: TypeCode.number)),
        Child('links', NodeMeta()),
      ]
      ..metas['$sys/cpu'] = NodeMeta(
        ty: TypeCode.number,
        unit: const TText('pct'),
        attr: {'description': const VStr('CPU of the broker process.')},
      )
      ..metas['$sys/links_connected'] = NodeMeta(
        ty: TypeCode.number,
        attr: {
          'description': const VStr(
            'Links whose liveliness token is present.',
          ),
        },
      );
    // the device profiles under `pub`
    if (f.profilesListed) {
      api
        ..children_['$plant/pub'] = [
          Child('acme:ahu', NodeMeta()),
          Child('acme:vav', NodeMeta()),
        ]
        ..metas['$plant/pub/acme:ahu'] = NodeMeta(childrenCount: 14)
        ..metas['$plant/pub/acme:vav'] = NodeMeta(childrenCount: 1);
    } else {
      api.errors['$plant/pub'] = WyrmException.of(
        Status.notFound,
        'pub is not listed',
      );
    }
    api.invokes['$sys/profiles ▸ remove'] = const [VNull()];
    // the kept backups (ADR 0048 §3.4)
    if (f.backups) {
      const sections = VArray([VStr('control'), VStr('keys')]);
      api
        ..metas['$sys/backups'] = NodeMeta(
          attr: {
            'sections': const VArray([
              VStr('control'),
              VStr('keys'),
              VStr('history'),
            ]),
            'keep_days': const VInt(7),
          },
        )
        ..children_['$sys/backups'] = [
          for (final id in ['b1', 'b2', 'b3', 'b4', 'b5'])
            Child(id, NodeMeta()),
        ];
      for (final (id, kind, link) in [
        ('b1', 'full', ''),
        ('b2', 'link', 'modbus'),
        ('b3', 'pre-update', ''),
        ('b4', 'pre-restore', ''),
        ('b5', 'full', ''),
      ]) {
        api.metas['$sys/backups/$id'] = NodeMeta(
          attr: {
            'kind': VStr(kind),
            'name': VStr('plant-$id.wyrm-backup'),
            'sections': sections,
            if (link.isNotEmpty) 'link': VStr(link),
          },
        );
      }
    } else {
      api.errors['$sys/backups'] = WyrmException.of(
        Status.notFound,
        'no sys/backups',
      );
    }
    // the log (get_log answers the newest last)
    api.answers['$sys ▸ get_log'] = (args) {
      logReads.add(args);
      return [
        Value.from([
          {
            'time': '2026-11-12T02:01:40Z',
            'level': 'warn',
            'target': 'wyrm_admin::supervisor',
            'message': 'link bacnet stopped: fuel limit reached',
          },
          {
            'time': '2026-11-12T02:01:44Z',
            'level': 'info',
            'target': 'wyrm_link_sdk',
            'message': 'link modbus connected',
          },
        ]),
      ];
    };
    api.invokes['$sys ▸ clear_conns'] = const [
      VArray([VStr('field-x')]),
    ];
  }

  /// The values `sys` publishes, as live values.
  Map<String, Object?> get _sysValues {
    final f = fixture;
    final (lag, forks) = switch (f.standby) {
      Standby.lag => (1240, 0),
      Standby.forks => (0, 1),
      Standby.both => (1240, 1),
      _ => (0, 0),
    };
    return {
      'version': '0.1.0',
      'zenoh_version': '1.10.1',
      'distribution': 'rust (prod)',
      'start_time': '2026-11-04T21:58:07Z',
      'uptime': 533000,
      'links_connected': 4,
      'links_total': 5,
      'quarantined': 2,
      'packages_total': 3,
      'upstream_connected': 1,
      'downstream_connected': 0,
      'sessions': 7,
      'cpu': 3.42,
      'memory': 412.5,
      'disk_free': 18432,
      'data_size': 842.3,
      'acl_denied': 18402,
      'audit_records': 1204,
      'standby_connected': f.standby == Standby.none ? 0 : 1,
      'standby_lag': lag,
      'standby_forks': forks,
      'arbiter_lease_s': f.lease,
      'log_level': f.level,
      'messages_in_per_second': 1520,
      'messages_out_per_second': 1490.5,
      'frames_in_per_second': 310,
      'frames_out_per_second': 302,
      'data_in_per_second': 81234,
      'data_out_per_second': 79000,
      'history/database_size': 310,
      'links/bacnet/state': 'failed',
      // the values of the kept backups
      'backups/b1/status': 'done',
      'backups/b1/size': 48213,
      'backups/b1/created': '2026-11-12T01:00:00Z',
      'backups/b2/status': 'running',
      'backups/b2/progress': 40,
      'backups/b3/status': 'failed',
      'backups/b4/status': 'done',
      'backups/b4/size': 3100000,
      'backups/b4/send_status': 'sending',
      'backups/b4/send_progress': 30,
      'backups/b5/status': 'done',
      'backups/b5/size': 812,
      'backups/b5/send_status': 'done',
    };
  }

  /// The links, quarantine entries and peers of the site.
  AppState _tables(AppState s) => s.copyWith(
    links: s.links.copyWith(
      table: IMap.fromValues(
        keyMapper: (l) => l.id,
        values: _links,
      ),
      view: [for (final l in _links) l.id].lock,
    ),
    quarantine: s.quarantine.copyWith(
      table: IMap.fromValues(keyMapper: (q) => q.node, values: _quarantine),
      view: [for (final q in _quarantine) q.node].lock,
    ),
    peers: s.peers.copyWith(
      table: IMap(const {
        'central': Peer(
          site: 'central',
          kind: PeerKind.upstream,
          connected: true,
        ),
      }),
      view: ['central'].lock,
    ),
    system: s.system.copyWith(
      aclSeen: fixture.aclSeen,
      trafficRoot: plant,
      samples: fixture.samples ? _samples : const IListConst([]),
    ),
  );

  List<LinkInfo> get _links => [
    const LinkInfo(id: 'modbus', state: 'connected'),
    const LinkInfo(id: 'bacnet', mode: LinkMode.wasm),
    const LinkInfo(id: 'mqtt', mode: LinkMode.external, state: 'connected'),
    for (var i = 0; i < fixture.stale; i++)
      LinkInfo(
        id: i == 0 ? 'field-x' : 'field-x$i',
        mode: LinkMode.external,
        state: 'disconnected',
        origin: 'runtime',
        certificateCn: i == 0 ? 'link:field-x' : null,
      ),
  ];

  List<QuarantineEntry> get _quarantine => [
    QuarantineEntry(
      cn: 'link:field-gw',
      node: 'field-gw',
      firstSeen: DateTime.utc(2026, 11, 12, 1, 20),
    ),
    QuarantineEntry(
      cn: 'broker:line2',
      node: 'line2',
      kind: QuarantineKind.broker,
      via: ['line3'].lock,
    ),
    const QuarantineEntry(
      cn: 'link:old',
      node: 'old',
      deauthorized: true,
    ),
  ];

  /// Twelve samples a minute apart from 01:50 UTC.
  IList<TrafficSample> get _samples => [
    for (var i = 0; i < 12; i++)
      TrafficSample(
        time: DateTime.utc(2026, 11, 12, 1, 50 + i),
        messagesIn: 1500.0 + i,
        messagesOut: 1490,
        framesIn: 300,
        framesOut: 301,
        dataIn: 81234,
        dataOut: 79000,
      ),
  ].lock;

  /// Logs in and lays the site's tables and values in.
  Future<void> _prepare(WidgetTester tester) async {
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
    store.dispatchSync(_Put(_tables));
    _values();
    store.dispatchSync(
      _Put((s) => s.copyWith.site(connected: fixture.connected)),
    );
  }

  /// The `sys` values as live values (what the broker sends again when a
  /// key is watched again).
  void _values() {
    final now = DateTime.utc(2026, 11, 12, 2, 2);
    store.dispatchSync(
      SetLiveValuesAction({
        if (fixture.values)
          for (final e in _sysValues.entries)
            '$sys/${e.key}': LiveValue(time: now, value: e.value),
      }),
    );
  }

  /// Logs in, lays the site's tables and values in, shows System in
  /// [locale] and opens [tab] as the user does, with its label.
  ///
  /// With [toasts] the toasts are drawn over it, as the shell draws them
  /// ([notices] reads them).
  Future<void> pump(
    WidgetTester tester, {
    SysTab tab = SysTab.overview,
    Locale locale = const Locale('en'),
    bool toasts = false,
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
            home: Scaffold(
              body: Stack(
                children: [
                  const SystemPageConnector(),
                  if (toasts)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: ToastStackConnector(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await open(tester, tab);
  }

  /// System inside Studio's own shell and router, so its links switch the
  /// workspace as they do in the app. The router is built once per test
  /// file ([createAppRouter]): call this once per file.
  Future<void> pumpInStudio(WidgetTester tester) async {
    await _prepare(tester);
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
    await toSystem(tester);
  }

  /// Back to the System workspace of the shell.
  Future<void> toSystem(WidgetTester tester) async {
    unawaited(appRouter.navigate(const StudioRoute(children: [SystemRoute()])));
    await settle(tester);
    _values();
    await settle(tester);
  }

  /// The workspace on screen in the shell (its route's name).
  String get workspace => appRouter.topRoute.name;

  /// Opens [tab] with its label (nothing for the Overview, shown first).
  Future<void> open(WidgetTester tester, SysTab tab) async {
    if (tab == SysTab.overview) {
      return;
    }
    await tester.tap(
      find.descendant(
        of: find.byType(SystemPage),
        matching: find.text(tab.label),
      ),
    );
    await settle(tester);
  }

  /// Lets the fake broker's answers arrive and the screen follow them,
  /// within one second of the clock (the Log tab reads every 5 s).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Takes System off the screen (its timers stop, it unwatches).
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  /// Every word on System, in the order of the tree.
  List<String> words(WidgetTester tester) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(SystemPage),
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

  /// The words of the toasts of success on screen (the failed reads of
  /// this fake broker are toasts of their own): each title, and its line.
  List<String> notices(WidgetTester tester) => [
    for (final v in tester.widget<ToastStack>(find.byType(ToastStack)).toasts)
      if (v.tone == Tone.good) ...[v.title, if (v.line.isNotEmpty) v.line],
  ];
}

/// Lays a state in, as the test needs it.
class _Put extends ReduxAction<AppState> {
  _Put(this.change);

  final AppState Function(AppState) change;

  @override
  AppState reduce() => change(state);
}
