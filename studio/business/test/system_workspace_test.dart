import 'dart:convert';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/system/actions/clear_conns_action.dart';
import 'package:business/redux/system/actions/poll_system_log_action.dart';
import 'package:business/redux/system/actions/put_profile_action.dart';
import 'package:business/redux/system/actions/remove_profile_action.dart';
import 'package:business/redux/system/actions/retrieve_profiles_action.dart';
import 'package:business/redux/system/actions/retrieve_sys_about_action.dart';
import 'package:business/redux/system/actions/retrieve_system_log_action.dart';
import 'package:business/redux/system/actions/sample_traffic_action.dart';
import 'package:business/redux/system/actions/set_acl_seen_action.dart';
import 'package:business/redux/system/actions/set_auto_action.dart';
import 'package:business/redux/system/actions/set_filter_action.dart';
import 'package:business/redux/system/actions/set_lines_action.dart';
import 'package:business/redux/system/actions/set_log_level_action.dart';
import 'package:business/redux/system/actions/set_shown_action.dart';
import 'package:business/redux/system/actions/set_source_action.dart';
import 'package:business/redux/system/actions/set_tab_action.dart';
import 'package:business/wyrm/mappers/log_line_mapper.dart';
import 'package:business/wyrm/mappers/profile_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/attention_kind.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/live_value.dart';
import 'package:models/log_line.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/standby_state.dart';
import 'package:models/workspace.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// The facade over one state, as an action or a connector reads it.
class _Read with Selectors {
  _Read(this.state);

  @override
  final AppState state;
}

const _sys = 'wy/central/sys';

void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  /// Live `sys` values, as the live service would hand them over.
  void sys(Map<String, Object?> values, {DateTime? at}) => s.dispatchSync(
    SetLiveValuesAction({
      for (final e in values.entries)
        '$_sys/${e.key}': LiveValue(
          time: at ?? DateTime.utc(2026, 11, 10, 1),
          value: e.value,
        ),
    }),
  );

  Map<String, Object?> lastArgs(String action) =>
      toPlain(api.calls.lastWhere((c) => c.action == action).args);

  group('get_log', () {
    Value record(String time, String level, String target, String message) =>
        Value.from({
          'time': time,
          'level': level,
          'target': target,
          'message': message,
        });

    test('sends the toolbar: lines, level, filter and the link', () async {
      api.invokes['$_sys ▸ get_log'] = [
        Value.from([
          {
            'time': '2026-11-10T01:12:18.000Z',
            'level': 'warn',
            'target': 'admin::peers',
            'message': 'upstream edge unreachable',
          },
          {
            'time': '2026-11-10T01:12:22.000Z',
            'level': 'info',
            'target': 'admin::peers',
            'message': 'upstream edge connected',
          },
        ]),
      ];
      s
        ..dispatchSync(SetSourceAction('scheduler'))
        ..dispatchSync(SetLogLevelAction('warn'))
        ..dispatchSync(SetFilterAction('edge'))
        ..dispatchSync(SetLinesAction(50));

      await s.dispatchAndWait(RetrieveSystemLogAction());

      expect(lastArgs('get_log'), {
        'lines': 50,
        'level': 'warn',
        'filter': 'edge',
        'link': 'scheduler',
      });
      // Newest first, with the four columns kept apart.
      expect(s.state.system.log.first.message, 'upstream edge connected');
      expect(s.state.system.log.last.level, 'warn');
      expect(s.state.system.log.last.target, 'admin::peers');
      expect(s.state.system.logError, isNull);
    });

    test('the whole broker: 200 lines by default and no link', () async {
      api.invokes['$_sys ▸ get_log'] = [];

      await s.dispatchAndWait(RetrieveSystemLogAction());

      expect(lastArgs('get_log'), {'lines': 200});
      expect(s.state.system.log, isEmpty);
    });

    test('a refusal is the log box message, not a dialog; the lines held '
        'stay', () async {
      api.invokes['$_sys ▸ get_log'] = [
        record('2026-11-10T01:00:00Z', 'info', 'wyrmd', 'up'),
      ];
      await s.dispatchAndWait(RetrieveSystemLogAction());
      api.errors['$_sys ▸ get_log'] = WyrmException.of(
        Status.permissionDenied,
        'config needed',
      );

      final status = await s.dispatchAndWait(RetrieveSystemLogAction());

      expect(status.isCompletedOk, isTrue);
      expect(s.state.system.logError, contains('config needed'));
      expect(s.state.system.log.single.message, 'up');

      api.errors.clear();
      await s.dispatchAndWait(RetrieveSystemLogAction());
      expect(s.state.system.logError, isNull);
    });

    test('the 5 s poll reads only while the Log tab is shown with '
        'auto-refresh on', () async {
      api.invokes['$_sys ▸ get_log'] = [];
      int reads() => api.calls.where((c) => c.action == 'get_log').length;

      await s.dispatchAndWait(PollSystemLogAction());
      expect(reads(), 0, reason: 'hidden');

      s
        ..dispatchSync(SetShownAction(true))
        ..dispatchSync(SetTabAction('overview'));
      await s.dispatchAndWait(PollSystemLogAction());
      expect(reads(), 0, reason: 'another tab');

      s.dispatchSync(SetTabAction('log'));
      await s.dispatchAndWait(PollSystemLogAction());
      expect(reads(), 1);

      s.dispatchSync(SetAutoAction(false));
      await s.dispatchAndWait(PollSystemLogAction());
      expect(reads(), 1, reason: 'auto-refresh off');
    });

    test('a poll is not a refresh of the workspace; Get log is', () async {
      api
        ..invokes['$_sys ▸ get_log'] = [
          record('2026-11-10T01:00:00Z', 'info', 'wyrmd', 'up'),
        ]
        ..delays['$_sys ▸ get_log'] = const Duration(milliseconds: 30);
      await s.dispatchAndWait(RetrieveSystemLogAction());
      s
        ..dispatchSync(SetShownAction(true))
        ..dispatchSync(SetTabAction('log'));

      final poll = s.dispatchAndWait(PollSystemLogAction());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(_Read(s.state).refreshing(Workspace.system), isFalse);
      await poll;

      final read = s.dispatchAndWait(RetrieveSystemLogAction());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(_Read(s.state).refreshing(Workspace.system), isTrue);
      await read;
    });

    test('Copy and Save write one record per line; the file is named by '
        'site and time', () {
      const lines = [
        LogLine(
          time: '2026-11-10T02:01:44Z',
          level: 'info',
          target: 'gateway',
          message: 'olena: set ok',
        ),
        LogLine(
          time: '2026-11-10T01:56:31Z',
          level: 'error',
          target: 'link{id=bacnet}',
          message: 'wasm component stopped',
        ),
      ];

      expect(
        logText(lines),
        '2026-11-10T02:01:44Z INFO gateway olena: set ok\n'
        '2026-11-10T01:56:31Z ERROR link{id=bacnet} wasm component stopped',
      );
      expect(
        logFileName('plant', DateTime(2026, 11, 10, 2, 5)),
        'wyrm-plant-20261110-0205.log',
      );
    });
  });

  group('clear_conns', () {
    LinkInfo link(
      String id, {
      LinkMode mode = LinkMode.external,
      String origin = 'runtime',
      String state = 'installed',
    }) => LinkInfo(id: id, mode: mode, origin: origin, state: state);

    void hold(List<LinkInfo> links) => s.dispatchSync(
      _Set(
        (st) => st.copyWith.links(
          table: IMap.fromValues(values: links, keyMapper: (l) => l.id),
          view: [for (final l in links) l.id].lock,
        ),
      ),
    );

    test("the list is the broker's own rule: external, admitted at "
        'runtime, not connected now', () {
      hold([
        link('meter-07'),
        link('field-gw', state: 'connected'),
        link('from-config', origin: 'config'),
        link('modbus', mode: LinkMode.embedded),
        link('pg', mode: LinkMode.process, state: 'failed'),
        link('field-gw-old', state: 'stopped'),
      ]);

      expect(
        [for (final l in _Read(s.state).clearableLinks) l.id],
        ['meter-07', 'field-gw-old'],
      );
    });

    test('a live state wins over the one read with the list', () {
      hold([link('meter-07'), link('field-gw', state: 'connected')]);
      // wyrm-admin STATES: 2 = connected, 4 = stopped.
      sys({'links/meter-07/state': 2, 'links/field-gw/state': 4});

      expect(
        [for (final l in _Read(s.state).clearableLinks) l.id],
        ['field-gw'],
      );
    });

    test("the origin comes from the link's meta", () async {
      api.children_['$_sys/links'] = [Child('meter-07', NodeMeta())];
      api.metas['$_sys/links/meter-07'] = NodeMeta(
        attr: {
          'driver': const VStr('external'),
          'mode': const VStr('external'),
          'origin': const VStr('runtime'),
        },
      );

      await s.dispatchAndWait(RetrieveLinksAction());

      expect(s.state.links.table['meter-07']!.origin, 'runtime');
      expect(_Read(s.state).clearableLinks.single.id, 'meter-07');
    });

    test('the answer is the ids the broker removed; the links are read '
        'again', () async {
      api
        ..invokes['$_sys ▸ clear_conns'] = [
          Value.from(['meter-07', 'field-gw-old']),
        ]
        ..children_['$_sys/links'] = [];

      final action = ClearConnsAction();
      final status = await s.dispatchAndWait(action);

      expect(status.isCompletedOk, isTrue);
      expect(action.removed, ['meter-07', 'field-gw-old']);
      expect(api.calls.any((c) => c.key == '$_sys/links'), isTrue);
    });

    test('nothing removed is an empty answer', () async {
      api
        ..invokes['$_sys ▸ clear_conns'] = []
        ..children_['$_sys/links'] = [];

      final action = ClearConnsAction();
      await s.dispatchAndWait(action);

      expect(action.removed, isEmpty);
    });
  });

  group('profiles', () {
    test('the names under pub, each with the points of its meta', () async {
      api
        ..children_['wy/central/pub'] = [
          Child('schneider:pm5560', NodeMeta()),
          Child('abb:m4m-30', NodeMeta()),
        ]
        ..metas['wy/central/pub/schneider:pm5560'] = NodeMeta(
          children: ['v1', 'v2', 'i1'],
        )
        ..metas['wy/central/pub/abb:m4m-30'] = NodeMeta(childrenCount: 36);

      await s.dispatchAndWait(RetrieveProfilesAction());

      final p = s.state.system.profiles;
      expect([for (final x in p) x.name], ['schneider:pm5560', 'abb:m4m-30']);
      expect([for (final x in p) x.points], [3, 36]);
      expect(s.state.system.profilesNote, isNull);
    });

    test('a broker that does not list pub leaves a note, no dialog', () async {
      final status = await s.dispatchAndWait(RetrieveProfilesAction());

      expect(status.isCompletedOk, isTrue);
      expect(s.state.system.profiles, isEmpty);
      expect(s.state.system.profilesNote, contains('not_found'));
    });

    test('put sends a .cbor file as it is', () async {
      api
        ..invokes['$_sys/profiles ▸ put'] = []
        ..children_['wy/central/pub'] = [];
      final bytes = Uint8List.fromList([0xa1, 0x01, 0x01]);

      await s.dispatchAndWait(
        PutProfileAction('abb:m4m-30', 'm4m.cbor', bytes),
      );

      final call = api.calls.lastWhere((c) => c.action == 'put');
      expect(call.key, '$_sys/profiles');
      expect(call.args!['name'], const VStr('abb:m4m-30'));
      expect((call.args!['profile']! as VBytes).v, bytes);
    });

    test('put encodes a JSON file as a ProfileDef', () async {
      api
        ..invokes['$_sys/profiles ▸ put'] = []
        ..children_['wy/central/pub'] = [];
      final json = utf8.encode(
        '{"extends": "wy:number", "type": "number", "unit": "°C", '
        '"cfg": {"min": -40}}',
      );

      await s.dispatchAndWait(
        PutProfileAction('acme:temp', 'temp.json', Uint8List.fromList(json)),
      );

      final sent =
          (api.calls.lastWhere((c) => c.action == 'put').args!['profile']!
                  as VBytes)
              .v;
      // The NodeMeta entries under their integer keys, then `extends`.
      final meta = NodeMeta.fromCbor(sent);
      expect(meta.ty, TypeCode.number);
      expect('${meta.unit}', '°C');
      expect(meta.cfg!['min'], const VInt(-40));
      expect(sent.first, 0xa0 + 4);
      expect(utf8.decode(sent, allowMalformed: true), contains('extends'));
      expect(utf8.decode(sent, allowMalformed: true), contains('wy:number'));
    });

    test('a JSON file that is not a profile is refused before the call', () {
      expect(
        () => profileBytes('x.json', Uint8List.fromList(utf8.encode('[1]'))),
        throwsA(isA<UserException>()),
      );
      expect(
        () => encodeProfile({'points': 3}),
        throwsA(isA<UserException>()),
      );
      expect(
        () => encodeProfile({'type': 'colour'}),
        throwsA(isA<UserException>()),
      );
    });

    test('remove names the profile', () async {
      api
        ..invokes['$_sys/profiles ▸ remove'] = []
        ..children_['wy/central/pub'] = [];

      await s.dispatchAndWait(RemoveProfileAction('carel:pco5'));

      expect(lastArgs('remove'), {'name': 'carel:pco5'});
    });
  });

  group('standby', () {
    test('unknown before the value, then none, following, behind', () {
      expect(_Read(s.state).standby, StandbyState.unknown);

      sys({'standby_connected': 0});
      expect(_Read(s.state).standby, StandbyState.none);

      sys({'standby_connected': 1, 'standby_lag': 0, 'standby_forks': 0});
      expect(_Read(s.state).standby, StandbyState.following);

      sys({'standby_lag': 1240});
      expect(_Read(s.state).standby, StandbyState.behind);

      sys({'standby_lag': 0, 'standby_forks': 1});
      expect(_Read(s.state).standby, StandbyState.behind);
    });
  });

  group('attention', () {
    test('nothing to look at with a standby that follows', () {
      sys({'standby_connected': 1, 'standby_lag': 0, 'standby_forks': 0});

      expect(_Read(s.state).attention, isEmpty);
    });

    test('the order: standby behind, failed links, quarantine, brokers '
        'waiting, ACL grown', () {
      s
        ..dispatchSync(
          _Set(
            (st) => st.copyWith
                .links(
                  table: const IMapConst({
                    'modbus': LinkInfo(id: 'modbus', state: 'connected'),
                    'bacnet': LinkInfo(id: 'bacnet', state: 'failed'),
                  }),
                  view: const IListConst(['modbus', 'bacnet']),
                )
                .copyWith
                .quarantine(
                  table: IMapConst({
                    'line2': const QuarantineEntry(
                      cn: 'broker:line2',
                      node: 'line2',
                      kind: 'broker',
                      via: IListConst(['cell-a']),
                    ),
                    'field-gw': QuarantineEntry(
                      cn: 'link:field-gw',
                      node: 'field-gw',
                      firstSeen: DateTime.utc(2026, 11, 10, 1, 20),
                    ),
                    'old': const QuarantineEntry(
                      cn: 'link:old',
                      node: 'old',
                      deauthorized: true,
                    ),
                  }),
                  view: const IListConst(['line2', 'field-gw', 'old']),
                ),
          ),
        )
        ..dispatchSync(SetAclSeenAction(3));
      sys({
        'standby_connected': 1,
        'standby_lag': 1240,
        'standby_forks': 1,
        'acl_denied': 5,
      });

      final a = _Read(s.state).attention;

      expect(
        [for (final x in a) x.kind],
        [
          AttentionKind.standbyBehind,
          AttentionKind.linkFailed,
          AttentionKind.quarantine,
          AttentionKind.brokerWaiting,
          AttentionKind.aclGrown,
        ],
      );
      expect((a[0].count, a[0].more), (1240, 1));
      expect(a[1].subject, 'bacnet');
      expect((a[2].subject, a[2].name), ('field-gw', 'link:field-gw'));
      expect(a[2].since, DateTime.utc(2026, 11, 10, 1, 20));
      expect((a[3].subject, a[3].count), ('line2', 1));
      expect((a[4].count, a[4].more), (2, 3));
    });

    test('no standby is the last card, and only once the value is known', () {
      expect(_Read(s.state).attention, isEmpty);

      s.dispatchSync(
        _Set(
          (st) => st.copyWith.links(
            table: const IMapConst({
              'bacnet': LinkInfo(id: 'bacnet', state: 'failed'),
            }),
            view: const IListConst(['bacnet']),
          ),
        ),
      );
      sys({'standby_connected': 0});

      expect(
        [for (final x in _Read(s.state).attention) x.kind],
        [
          AttentionKind.linkFailed,
          AttentionKind.noStandby,
        ],
      );
    });

    test('ACL denials count only when grown since the screen was left', () {
      sys({'standby_connected': 1, 'acl_denied': 5});
      expect(_Read(s.state).attention, isEmpty, reason: 'never left yet');

      s.dispatchSync(SetAclSeenAction(5));
      expect(_Read(s.state).attention, isEmpty, reason: 'not grown');

      sys({'acl_denied': 6});
      expect(_Read(s.state).attention.single.kind, AttentionKind.aclGrown);
    });
  });

  group('traffic ring', () {
    Map<String, Object?> rates(double base) => {
      for (final (i, k) in SampleTrafficAction.keys.indexed) k: base + i,
    };

    test('the first tick watches the six rates of the site on screen', () {
      s.dispatchSync(SampleTrafficAction());

      expect(s.state.system.trafficRoot, 'wy/central');
      expect(
        s.state.live.watched.keys,
        containsAll([
          '$_sys/messages_in_per_second',
          '$_sys/data_out_per_second',
        ]),
      );
      expect(s.state.live.watched, hasLength(6));
      expect(s.state.system.samples, isEmpty);
    });

    test('one sample per value the broker publishes, none for a tick '
        'without news', () {
      s.dispatchSync(SampleTrafficAction());
      sys(rates(100), at: DateTime.utc(2026, 11, 10, 1, 0, 5));
      s
        ..dispatchSync(SampleTrafficAction())
        ..dispatchSync(SampleTrafficAction());

      expect(s.state.system.samples, hasLength(1));
      final first = s.state.system.samples.single;
      expect((first.messagesIn, first.messagesOut), (100, 101));
      expect((first.framesIn, first.framesOut), (102, 103));
      expect((first.dataIn, first.dataOut), (104, 105));

      sys(rates(200), at: DateTime.utc(2026, 11, 10, 1, 0, 10));
      s.dispatchSync(SampleTrafficAction());

      expect(s.state.system.samples, hasLength(2));
      expect(s.state.system.samples.last.messagesIn, 200);
    });

    test('the ring holds one hour', () {
      s.dispatchSync(SampleTrafficAction());
      final start = DateTime.utc(2026, 11, 10);
      for (final minutes in [0, 30, 59, 61, 90]) {
        sys(rates(1), at: start.add(Duration(minutes: minutes)));
        s.dispatchSync(SampleTrafficAction());
      }

      expect(
        [for (final x in s.state.system.samples) x.time.difference(start)],
        const [
          Duration(minutes: 30),
          Duration(minutes: 59),
          Duration(minutes: 61),
          Duration(minutes: 90),
        ],
      );
    });

    test('the ring is kept while another screen is shown', () {
      s.dispatchSync(SampleTrafficAction());
      sys(rates(1), at: DateTime.utc(2026, 11, 10, 1));
      s
        ..dispatchSync(SampleTrafficAction())
        ..dispatchSync(SetShownAction(false))
        ..dispatchSync(SetTabAction('log'));
      sys(rates(2), at: DateTime.utc(2026, 11, 10, 1, 0, 5));
      s.dispatchSync(SampleTrafficAction());

      expect(s.state.system.samples, hasLength(2));
    });
  });

  group('sys descriptions', () {
    test('the description and unit of every value node, read once', () async {
      api
        ..children_[_sys] = [
          Child('cpu', NodeMeta(ty: TypeCode.number)),
          Child('links', NodeMeta()),
        ]
        ..metas['$_sys/cpu'] = NodeMeta(
          ty: TypeCode.number,
          unit: const TText('%'),
          attr: {
            'description': const VStr('CPU time of the broker process.'),
          },
        );

      await s.dispatchAndWait(RetrieveSysAboutAction());
      await s.dispatchAndWait(RetrieveSysAboutAction());

      expect(
        s.state.system.about['$_sys/cpu'],
        'CPU time of the broker process.',
      );
      expect(s.state.system.units['$_sys/cpu'], '%');
      expect(api.calls.where((c) => c.key == '$_sys/cpu'), hasLength(1));
      expect(api.calls.any((c) => c.key == '$_sys/links'), isFalse);
    });
  });
}

/// A CBOR value as plain Dart, for comparing arguments.
Map<String, Object?> toPlain(Value? v) => switch (v) {
  VMap(:final v) => {
    for (final e in v.entries)
      e.key: switch (e.value) {
        VStr(:final v) => v,
        VInt(:final v) => v,
        VBool(:final v) => v,
        final other => other,
      },
  },
  _ => const {},
};

/// Puts a state in place, as a retrieve would have.
class _Set extends ReduxAction<AppState> {
  _Set(this.change);

  final AppState Function(AppState) change;

  @override
  AppState reduce() => change(state);
}
