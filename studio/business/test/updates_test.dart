import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/updates/actions/close_update_action.dart';
import 'package:business/redux/updates/actions/open_update_action.dart';
import 'package:business/redux/updates/actions/rollback_package_action.dart';
import 'package:business/redux/updates/actions/set_accept_new_action.dart';
import 'package:business/redux/updates/actions/set_auto_rollback_action.dart';
import 'package:business/redux/updates/actions/set_take_point_action.dart';
import 'package:business/redux/updates/actions/update_package_action.dart';
import 'package:business/wyrm/mappers/package_info_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/package_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _pkg = 'wy/central/sys/packages/modbus';

Value _report(String result, {int at = 100}) => VMap({
  'from': const VStr('0.4.2'),
  'to': const VStr('0.5.0'),
  'at': VInt(at),
  'result': VStr(result),
  'kept': const VInt(226),
  'new': const VInt(4),
  'gone': const VInt(0),
  'new_keys': const VArray([VStr('modbus/ip1/~act/read_write')]),
  'gone_keys': const VArray([]),
  'reason': const VStr(''),
  'links': const VArray([VStr('modbus'), VStr('line2')]),
  'changes_state': const VBool(false),
  'restore_point': const VBool(true),
});

/// ADR 0048 §1: the update sheet's actions against a fake session.
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
    api.children_['wy/central/sys/packages'] = [];
  });

  Call lastInvoke() => api.calls.lastWhere((c) => c.op == 'invoke');

  test('the values of a package overlay its meta', () {
    final p = packageLive(
      const PackageInfo(name: 'modbus', version: '0.4.2'),
      (leaf) => switch (leaf) {
        'latest' => '0.5.0',
        'update_available' => true,
        'changes_state' => true,
        'state' => 3,
        'previous' => {
          'version': '0.4.1',
          'keep_until': 1700000000,
          'changes_state': false,
        },
        'last_update' => {
          'from': '0.4.1',
          'to': '0.4.2',
          'at': 5,
          'result': 'checking',
          'new': 2,
          'gone_keys': ['modbus/a'],
        },
        _ => null,
      },
    );
    expect(p.version, '0.4.2');
    expect(p.latest, '0.5.0');
    expect(p.updateAvailable, isTrue);
    expect(p.changesState, isTrue);
    expect(p.state, 3);
    expect(p.previous, '0.4.1');
    expect(p.keepUntil, 1700000000);
    expect(p.lastUpdate!.result, 'checking');
    expect(p.lastUpdate!.added, 2);
    expect(p.lastUpdate!.goneKeys, ['modbus/a']);
  });

  test('an empty previous and last_update read as none', () {
    final p = packageLive(
      const PackageInfo(name: 'x'),
      (leaf) => leaf == 'previous' || leaf == 'last_update'
          ? <String, Object?>{}
          : null,
    );
    expect(p.previous, isNull);
    expect(p.lastUpdate, isNull);
  });

  test('restore points are read newest first as the broker lists them', () {
    final points = restorePointsOf([
      {'at': 20, 'version': '0.4.2', 'size': 3000},
      {'at': 10, 'version': '', 'size': 10},
    ]);
    expect(points.map((p) => p.at), [20, 10]);
    expect(points.last.version, '');
  });

  test('sys/links gives updates_available as an attribute', () async {
    api.children_['wy/central/sys/links'] = [];
    api.metas['wy/central/sys/links'] = NodeMeta(
      attr: {'updates_available': const VInt(3)},
    );

    await s.dispatchAndWait(RetrieveLinksAction());

    expect(s.state.links.updatesAvailable, 3);
  });

  test('a broker without the attribute counts no update', () async {
    api.children_['wy/central/sys/links'] = [];

    final status = await s.dispatchAndWait(RetrieveLinksAction());

    expect(status.isCompletedOk, isTrue);
    expect(s.state.links.updatesAvailable, 0);
  });

  test('Update sends the three options and then follows', () async {
    api
      ..initial['$_pkg/last_update'] = [
        ValSample('$_pkg/last_update', Sample(_report('ok', at: 50), t: 1)),
      ]
      ..invokes['$_pkg ▸ update'] = [
        const VMap({
          'success': VBool(true),
          'message': VStr(
            'modbus 0.5.0 installed; the links are being checked',
          ),
        }),
      ];
    s
      ..dispatchSync(OpenUpdateAction('modbus'))
      ..dispatchSync(SetAutoRollbackAction(false));

    final status = await s.dispatchAndWait(UpdatePackageAction());

    expect(status.isCompletedOk, isTrue);
    final call = lastInvoke();
    expect(call.action, 'update');
    expect(call.args!['restore_point'], const VBool(true));
    expect(call.args!['auto_rollback_s'], const VInt(0));
    expect(call.args!['accept'], isNull);
    expect(s.state.updates.view, 'follow');
    // The report that was there before is the one to wait past.
    expect(s.state.updates.seenAt, 50);
    expect(s.state.updates.message, contains('being checked'));
  });

  test(
    'an answer without success keeps the review with what it asks',
    () async {
      api.invokes['$_pkg ▸ update'] = [
        const VMap({
          'success': VBool(false),
          'message': VStr('modbus 0.5.0 asks for more: net 10.0.5.0/24'),
        }),
      ];
      s.dispatchSync(OpenUpdateAction('modbus'));

      await s.dispatchAndWait(UpdatePackageAction());

      expect(s.state.updates.view, 'review');
      expect(s.state.updates.asks, contains('10.0.5.0/24'));

      // Accepted, the next call carries `accept`.
      api.invokes['$_pkg ▸ update'] = [
        const VMap({'success': VBool(true), 'message': VStr('ok')}),
      ];
      s.dispatchSync(SetAcceptNewAction(true));
      await s.dispatchAndWait(UpdatePackageAction());

      expect(lastInvoke().args!['accept'], const VBool(true));
      expect(s.state.updates.view, 'follow');
      expect(s.state.updates.asks, isNull);
    },
  );

  test('a refusal goes back to the review and fails the action', () async {
    api.errors['$_pkg ▸ update'] = WyrmException.of(Status.busy, 'checking');
    s.dispatchSync(OpenUpdateAction('modbus'));

    final status = await s.dispatchAndWait(UpdatePackageAction());

    expect(status.isCompletedFailed, isTrue);
    expect(s.state.updates.view, 'review');
  });

  test('a queue updates one package after another', () async {
    const other = 'wy/central/sys/packages/telegram';
    for (final key in [_pkg, other]) {
      api
        ..initial['$key/last_update'] = [
          ValSample('$key/last_update', Sample(_report('ok', at: 7), t: 1)),
        ]
        ..invokes['$key ▸ update'] = [
          const VMap({'success': VBool(true), 'message': VStr('ok')}),
        ];
    }
    s.dispatchSync(OpenUpdateAction('modbus', queue: const ['telegram']));

    final run = s.dispatchAndWait(
      UpdatePackageAction(settle: const Duration(milliseconds: 5)),
    );
    // The first package's check ends: its report is a new one.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    api.initial['$_pkg/last_update'] = [
      ValSample('$_pkg/last_update', Sample(_report('ok', at: 8), t: 2)),
    ];
    api.subs.remove('$_pkg/last_update');
    await run;

    final updated = [
      for (final c in api.calls)
        if (c.action == 'update') c.key,
    ];
    expect(updated, [_pkg, other]);
    expect(s.state.updates.package, 'telegram');
    expect(s.state.updates.queue, isEmpty);
  });

  test(
    'a custom package is updated by install_zip on one of its links',
    () async {
      api
        ..children_['wy/central/sys/links'] = [Child('avg1', NodeMeta())]
        ..metas['wy/central/sys/links/avg1'] = NodeMeta(
          attr: {
            'driver': const VStr('pkg:counter-avg'),
            'mode': const VStr('process'),
          },
        )
        ..invokes['wy/central/sys/links ▸ install_zip'] = [
          const VMap({'success': VBool(true), 'message': VStr('ok')}),
        ];
      await s.dispatchAndWait(RetrieveLinksAction());
      s
        ..dispatchSync(OpenUpdateAction('counter-avg'))
        ..dispatchSync(SetTakePointAction(false));

      await s.dispatchAndWait(
        UpdatePackageAction(zip: Uint8List.fromList([80, 75, 3, 4])),
      );

      final call = lastInvoke();
      expect(call.key, 'wy/central/sys/links');
      expect(call.action, 'install_zip');
      expect(call.args!['name'], const VStr('avg1'));
      expect(call.args!['restore_point'], const VBool(false));
      expect(call.args!['auto_rollback_s'], const VInt(120));
    },
  );

  test('Roll back calls the package and follows its new report', () async {
    api
      ..initial['$_pkg/last_update'] = [
        ValSample('$_pkg/last_update', Sample(_report('ok', at: 9), t: 1)),
      ]
      ..invokes['$_pkg ▸ rollback'] = [
        const VMap({'success': VBool(true), 'message': VStr('rolled back')}),
      ];
    s.dispatchSync(OpenUpdateAction('modbus', follow: true));

    final status = await s.dispatchAndWait(RollbackPackageAction('modbus'));

    expect(status.isCompletedOk, isTrue);
    expect(lastInvoke().action, 'rollback');
    expect(s.state.updates.seenAt, 9);
    expect(s.state.updates.view, 'follow');
  });

  test('a refused rollback fails and says why', () async {
    api.invokes['$_pkg ▸ rollback'] = [
      const VMap({
        'success': VBool(false),
        'message': VStr('modbus: no restore point'),
      }),
    ];

    final status = await s.dispatchAndWait(RollbackPackageAction('modbus'));

    expect(status.isCompletedFailed, isTrue);
  });

  test('Close forgets the sheet', () {
    s
      ..dispatchSync(OpenUpdateAction('modbus'))
      ..dispatchSync(CloseUpdateAction());
    expect(s.state.updates.package, isNull);
  });
}
