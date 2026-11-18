import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/estimate_backup_action.dart';
import 'package:business/redux/backups/actions/open_backup_action.dart';
import 'package:business/redux/backups/actions/retrieve_backups_action.dart';
import 'package:business/redux/historian/actions/retrieve_historian_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/peers/actions/retrieve_peers_action.dart';
import 'package:business/redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'package:business/redux/site/actions/retrieve_sites_action.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/unreadable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/backups_read.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _root = 'wy/central';

/// Entries of a list Studio cannot read are not shown, and do not vanish
/// either (audit of #135): the others are shown, and the user is told
/// which were not, by a toast and a line in Problems the app words.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    final login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  /// The problems of entries not read, newest first.
  List<StudioError> unread() => [
    for (final e in s.state.problems.items)
      if (e.hint == ErrorHint.unreadableRows) e,
  ];

  NodeMeta broker([Map<String, Value> attr = const {}]) =>
      NodeMeta(is_: const TText('wy:broker'), attr: attr);

  test('Unread keeps the names of what was not read', () {
    final u = Unread();
    expect(u.take(const Valid(1), name: 'a', where: 'w'), 1);
    expect(u.any, isFalse);
    expect(u.problem(key: '$_root/sys/x', call: 'list'), isNull);
    expect(
      u.take(const Invalid<int>('s', 'f', 'r'), name: 'b', where: 'w'),
      isNull,
    );
    expect(
      u.take(const Invalid<int>('s', 'f', 'r'), name: 'c', where: 'w'),
      isNull,
    );
    expect(u.names, ['b', 'c']);
    final p = u.problem(key: '$_root/sys/x', call: 'list')!;
    expect(
      (p.kind, p.hint, p.key, p.call, p.thing, p.site, p.quiet),
      (
        ErrorKind.broker,
        ErrorHint.unreadableRows,
        '$_root/sys/x',
        'list',
        'b, c',
        'central',
        true,
      ),
    );
    // business says it in no words of its own
    expect(p.message, isEmpty);
  });

  test('quarantine: the entries not read are named', () async {
    api.children_['$_root/sys/quarantine'] = [
      Child('plc-gw-7', NodeMeta()),
      Child('gw-9', NodeMeta()),
      Child('old', NodeMeta()),
    ];
    api.metas['$_root/sys/quarantine/plc-gw-7'] = NodeMeta(
      attr: {'kind': const VStr('link')},
    );
    api.metas['$_root/sys/quarantine/gw-9'] = NodeMeta(
      attr: {'kind': const VStr('gateway')},
    );
    api.metas['$_root/sys/quarantine/old'] = NodeMeta();

    await s.dispatchAndWait(RetrieveQuarantineAction());

    expect(s.state.quarantine.view, ['plc-gw-7']);
    final p = unread().single;
    expect(p.key, '$_root/sys/quarantine');
    expect(p.thing, 'gw-9, old');
    // a toast is raised for it
    expect(s.state.problems.toasts, contains(p.id));

    // all read: nothing is said
    api.metas['$_root/sys/quarantine/gw-9'] = NodeMeta(
      attr: {'kind': const VStr('broker')},
    );
    api.metas['$_root/sys/quarantine/old'] = NodeMeta(
      attr: {'kind': const VStr('link')},
    );
    final before = s.state.problems.items.length;
    await s.dispatchAndWait(RetrieveQuarantineAction());
    expect(s.state.quarantine.view, ['plc-gw-7', 'gw-9', 'old']);
    expect(s.state.problems.items, hasLength(before));
  });

  test('Sites: an upstream and a broker below that are not read', () async {
    ValSample at(String key, Value v) => ValSample(key, Sample(v, t: 1));
    api
      ..children_['$_root/sys/upstream'] = [
        Child('hq', NodeMeta()),
        Child('lab', NodeMeta()),
      ]
      ..initial['$_root/sys/upstream/*/*'] = [
        at('$_root/sys/upstream/hq/url', const VStr('quic://hq:7447')),
        at('$_root/sys/upstream/hq/enabled', const VBool(true)),
        // not a bool: not taken as enabled
        at('$_root/sys/upstream/lab/enabled', const VStr('yes')),
      ]
      ..initial['$_root/sys/upstream_connected'] = [
        at('$_root/sys/upstream_connected', const VInt(1)),
      ]
      ..children_['$_root/downstream'] = [
        Child('plant', broker({'site': const VStr('plant')})),
        Child('odd', broker({'site': const VInt(7)})),
      ];

    await s.dispatchAndWait(RetrievePeersAction());

    expect(s.state.peers.view, ['upstream:hq', 'downstream:plant']);
    expect(s.state.peers.table['upstream:hq']!.connected, isTrue);
    final p = unread().single;
    expect(p.key, _root);
    expect(p.thing, 'sys/upstream/lab, downstream/odd');
  });

  test('the sites to choose: a broker node that is not read', () async {
    api.children_['$_root/downstream'] = [
      Child('plant', broker({'site': const VStr('plant')})),
      Child('odd', broker({'site': const VInt(7)})),
    ];

    await s.dispatchAndWait(RetrieveSitesAction());

    expect(s.state.site.choices.map((c) => c.site), contains('plant'));
    expect(s.state.site.choices.map((c) => c.site), isNot(contains('odd')));
    expect(unread().single.thing, 'central/downstream/odd');
  });

  test('History: a group and a statistic that are not read', () async {
    ValSample at(String key, Value v) => ValSample(key, Sample(v, t: 1));
    const base = '$_root/sys/history';
    api
      ..children_[base] = [
        Child('fast', NodeMeta()),
        Child('slow', NodeMeta()),
      ]
      ..children_['$base/fast'] = []
      ..children_['$base/slow'] = []
      ..initial['$base/*'] = [
        at('$base/retention_days', const VInt(90)),
        at('$base/odd', const VMap({})),
      ]
      ..initial['$base/*/*'] = [
        at('$base/fast/logging_type', const VStr('Interval')),
        at('$base/fast/interval', const VInt(5)),
        at('$base/slow/interval', const VStr('5 s')),
      ];

    await s.dispatchAndWait(RetrieveHistorianAction());

    expect(s.state.historian.groups.map((g) => g.name), ['fast']);
    expect(s.state.historian.stats.unlock, {'retention_days': '90'});
    final p = unread().single;
    expect(p.key, base);
    expect(p.thing, 'slow, odd');
  });

  group('sys/backups', () {
    const b = '$_root/sys/backups';

    test('a kept backup Studio cannot read stays in the list as not '
        'read', () async {
      api
        ..metas[b] = NodeMeta(
          attr: {
            'sections': const VArray([VStr('control'), VStr('storage')]),
          },
        )
        ..children_[b] = [
          Child('b1', NodeMeta()),
          Child('b2', NodeMeta()),
          Child('b3', NodeMeta()),
          Child('b4', NodeMeta()),
        ]
        ..metas['$b/b1'] = NodeMeta(attr: {'kind': const VStr('full')})
        ..metas['$b/b2'] = NodeMeta(attr: {'kind': const VStr('snapshot')})
        ..metas['$b/b3'] = NodeMeta(attr: {'sealed': const VStr('hsm')})
        ..metas['$b/b4'] = NodeMeta(
          attr: {
            'sections': const VArray([VStr('control'), VStr('flows')]),
          },
        );

      await s.dispatchAndWait(RetrieveBackupsAction());

      final st = s.state.backups;
      expect(st.availability, BackupsRead.read);
      expect(st.view, ['b1']);
      // not dropped: each is there for the screen to say so
      expect(st.unread, ['b2', 'b3', 'b4']);
      final p = unread().single;
      expect((p.key, p.thing), (b, 'b2, b3, b4'));
      expect(s.state.problems.toasts, contains(p.id));
    });

    test('attributes Studio cannot read are "not read", not a broker '
        'without backups', () async {
      api
        ..children_[b] = [Child('b1', NodeMeta())]
        ..metas['$b/b1'] = NodeMeta()
        ..metas[b] = NodeMeta(
          attr: {
            'sections': const VArray([VStr('control'), VStr('flows')]),
          },
        );

      await s.dispatchAndWait(RetrieveBackupsAction());

      expect(s.state.backups.availability, BackupsRead.unreadable);
      expect(s.state.backups.sections, isEmpty);
      final said = s.state.problems.items.first;
      expect(
        (said.hint, said.key, said.call, said.quiet),
        (ErrorHint.unreadableAnswer, b, 'meta', true),
      );

      // read again once the broker answers in a form Studio reads
      api.metas[b] = NodeMeta(
        attr: {
          'sections': const VArray([VStr('control')]),
        },
      );
      await s.dispatchAndWait(RetrieveBackupsAction());
      expect(s.state.backups.availability, BackupsRead.read);
      expect(s.state.backups.view, ['b1']);
    });

    test('a broker without sys/backups has none', () async {
      api.errors[b] = WyrmException.of(Status.notFound, 'no node');

      await s.dispatchAndWait(RetrieveBackupsAction());

      expect(s.state.backups.availability, BackupsRead.absent);
      expect(unread(), isEmpty);
    });
  });

  test('an estimate that is not read is refused and said', () async {
    const b = '$_root/sys/backups';
    api
      ..children_[b] = []
      ..metas[b] = NodeMeta(
        attr: {
          'sections': const VArray([VStr('control'), VStr('storage')]),
        },
      )
      ..invokes['$b ▸ estimate'] = [
        const VMap({
          'sections': VMap({'control': VInt(1200), 'flows': VInt(9)}),
        }),
      ];
    await s.dispatchAndWait(RetrieveBackupsAction());
    s.dispatchSync(OpenBackupAction());
    expect(s.state.backups.sections, hasLength(2));

    final status = await s.dispatchAndWait(EstimateBackupAction());

    expect(status.isCompletedFailed, isTrue);
    expect(s.state.backups.estimate, isEmpty);
    final said = s.state.problems.items.first;
    expect(said.hint, ErrorHint.unreadableAnswer);
    expect((said.key, said.call), (b, 'estimate'));
  });
}
