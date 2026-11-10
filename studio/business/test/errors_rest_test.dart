import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/link_install/actions/install_link_action.dart';
import 'package:business/redux/link_install/actions/set_name_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/nodes/actions/retry_read_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/redux/system/actions/set_around_action.dart';
import 'package:business/wyrm/mappers/log_line_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/install_source.dart';
import 'package:models/log_line.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

class _Set extends Action {
  _Set(this.change);

  final AppState Function(AppState state) change;

  @override
  AppState reduce() => change(state);
}

int _count(FakeWyrmApi api, String op, String key) =>
    api.calls.where((c) => c.op == op && c.key == key).length;

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

  group('read failed on a node (errors.md §4)', () {
    const dev = 'wy/central/downstream/modbus/plc1';

    test('a list that fails marks the node and is a quiet problem with '
        'Try again; the list answering clears the mark', () async {
      api.metas[dev] = NodeMeta();
      s.dispatchSync(SelectNodeAction(dev));
      await Future<void>.delayed(Duration.zero);
      api.lists[dev]!.addError(WyrmException.of(Status.timeout, 'slow'));
      await Future<void>.delayed(Duration.zero);

      expect(s.state.nodes.listFailed[dev], 'timeout');
      final e = s.state.problems.items.firstWhere((p) => p.call == 'list');
      expect(e.key, dev);
      expect(e.quiet, isTrue);
      expect(e.retry, isNotNull);

      // Try again in Problems opens the list again.
      final before = _count(api, 'list', dev);
      await s.dispatchAndWait(RetryProblemAction(e.id));
      expect(_count(api, 'list', dev), before + 1);
      expect(s.state.nodes.listFailed[dev], 'timeout', reason: 'no answer yet');

      api.lists[dev]!.add(const ListRefreshed([]));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.nodes.listFailed, isEmpty);
    });

    test('a node the user may not list is empty, without a mark', () async {
      api.metas[dev] = NodeMeta();
      s.dispatchSync(SelectNodeAction(dev));
      await Future<void>.delayed(Duration.zero);
      api.lists[dev]!.addError(WyrmException.of(Status.permissionDenied, ''));
      await Future<void>.delayed(Duration.zero);

      expect(s.state.nodes.listFailed, isEmpty);
    });

    test('the meta of the selected node: no dialog, the mark, a toast; '
        'Read again reads it and clears the mark', () async {
      api.errors[dev] = WyrmException.of(Status.notAvailable, 'link is down');
      s.dispatchSync(SelectNodeAction(dev));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.state.nodes.metaFailed[dev], 'not_available');
      final e = s.state.problems.items.firstWhere((p) => p.call == 'meta');
      expect(e.quiet, isTrue, reason: 'nobody asked for this read');
      expect(s.state.problems.toasts, contains(e.id));
      expect(s.getAndRemoveFirstError(), isNull, reason: 'no dialog');

      api.errors.remove(dev);
      api.metas[dev] = NodeMeta();
      s.dispatchSync(RetryReadAction(dev));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.state.nodes.metaFailed, isEmpty);
      expect(s.state.nodes.detail.containsKey(dev), isTrue);
    });

    test('the meta a form needs keeps its dialog, and marks the node '
        'too', () async {
      api.errors[dev] = WyrmException.of(Status.notFound, 'gone');
      final st = await s.dispatchAndWait(RetrieveNodeDetailAction(dev));

      expect(st.isCompletedFailed, isTrue);
      expect(s.state.nodes.metaFailed[dev], 'not_found');
      expect(s.getAndRemoveFirstError(), isNotNull);
    });

    test('a value: Read again subscribes again; a value clears the '
        'mark', () async {
      const key = '$dev/t2';
      s.dispatchSync(WatchKeysAction([key]));
      api.subs[key]!.addError(WyrmException.of(Status.notFound, 'no node'));
      await Future<void>.delayed(Duration.zero);
      expect(s.state.live.failed[key], 'not_found');
      expect(
        s.state.problems.items.firstWhere((p) => p.key == key).retry,
        isNotNull,
      );

      final before = _count(api, 'subscribe', key);
      s.dispatchSync(RetryReadAction(key));
      expect(_count(api, 'subscribe', key), before + 1);

      api.subs[key]!.add(
        const ValSample(key, Sample(VInt(4), t: 1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(s.state.live.failed, isEmpty);
    });

    test('Read again on a node with no failed read does nothing', () {
      final before = api.calls.length;
      s.dispatchSync(RetryReadAction(dev));
      expect(api.calls.length, before);
    });
  });

  group('Add a link: the refused answer (errors.md §3)', () {
    const links = 'wy/central/sys/links';

    void answers({required String path, InstallSource? source}) =>
        s.dispatchSync(
          _Set(
            (st) => st.copyWith.linkInstall(
              path: path,
              item: 'driver:modbus',
              name: 'Bad Name',
              broker: 'central',
              source: source,
              step: 2,
            ),
          ),
        );

    test('the name the broker refused is kept with its words; a new name '
        'takes them away', () async {
      answers(path: 'official');
      api.errors['$links ▸ install'] = WyrmException.of(
        Status.invalidParameter,
        'id: only lowercase letters, digits and `-`',
      );
      await s.dispatchAndWait(InstallLinkAction());

      final li = s.state.linkInstall;
      expect(li.phase, 'failed');
      expect(li.name, 'Bad Name', reason: 'the answers stay');
      expect(li.refusedField, 'name');
      expect(li.refusedSaid, 'only lowercase letters, digits and `-`');

      s.dispatchSync(SetNameAction('good-name'));
      expect(s.state.linkInstall.refusedField, isNull);
      expect(s.state.linkInstall.refusedSaid, isNull);
    });

    test('a refused URL is the field of the source in use', () async {
      answers(
        path: 'custom',
        source: const InstallSource.git(url: 'ftp://x', ref: 'main'),
      );
      api.errors['$links ▸ install_git'] = WyrmException.of(
        Status.invalidParameter,
        'url: only https',
      );
      await s.dispatchAndWait(InstallLinkAction());
      expect(s.state.linkInstall.refusedField, 'git');
      expect(s.state.linkInstall.refusedSaid, 'only https');

      // The name changing does not clear what was said of the URL.
      s.dispatchSync(SetNameAction('other'));
      expect(s.state.linkInstall.refusedField, 'git');
      s.dispatchSync(
        SetSourceAction(const InstallSource.git(url: 'https://x')),
      );
      expect(s.state.linkInstall.refusedField, isNull);
    });

    test('a refusal that names no field of the wizard marks none; a new '
        'run clears the last', () async {
      answers(path: 'official');
      api.errors['$links ▸ install'] = WyrmException.of(
        Status.invalidParameter,
        'driver: unknown',
      );
      await s.dispatchAndWait(InstallLinkAction());
      expect(s.state.linkInstall.refusedField, isNull);
      expect(s.state.linkInstall.message, 'invalid_parameter: driver: unknown');

      api.errors['$links ▸ install'] = WyrmException.of(
        Status.internalError,
        'name: disk full',
      );
      await s.dispatchAndWait(InstallLinkAction());
      expect(
        s.state.linkInstall.refusedField,
        isNull,
        reason: 'only a refusal of the input names a field',
      );
    });
  });

  group('the Log toolbar time (errors.md §3, Open the log)', () {
    LogLine at(String time) => LogLine(time: time, level: 'info');
    final lines = [
      at('2026-11-10T11:58:00Z'),
      at('2026-11-10T11:54:04Z'),
      at('2026-11-10T11:52:10Z'),
      at('2026-11-10T11:50:04Z'),
      at('2026-11-10T11:50:03Z'),
      at('not a time'),
    ];

    test('keeps the lines within two minutes of it, in their order', () {
      expect(
        [for (final l in linesAround(lines, '11:52:04')) l.time],
        [
          '2026-11-10T11:54:04Z',
          '2026-11-10T11:52:10Z',
          '2026-11-10T11:50:04Z',
        ],
      );
      expect(linesAround(lines, '11:52').length, 3);
    });

    test('no time, or text that is not one, keeps every line', () {
      expect(linesAround(lines, null).length, lines.length);
      expect(linesAround(lines, '').length, lines.length);
      expect(linesAround(lines, 'noon').length, lines.length);
      expect(linesAround(lines, '25:00').length, lines.length);
    });

    test('a window across midnight is one window; an offset is read as '
        'UTC', () {
      final night = [
        at('2026-11-10T23:59:30Z'),
        at('2026-11-11T00:01:00Z'),
        at('2026-11-11T02:00:10+02:00'),
        at('2026-11-11T00:03:00Z'),
      ];
      expect(linesAround(night, '00:00:30').length, 3);
    });

    test('the clock of an error is the rows clock, UTC', () {
      expect(logClockOf(DateTime.utc(2026, 11, 10, 9, 5, 7)), '09:05:07');
      final local = DateTime(2026, 11, 10, 11, 52, 4);
      final utc = local.toUtc();
      expect(
        secondOfDay(logClockOf(local)),
        utc.hour * 3600 + utc.minute * 60 + 4,
      );
      expect(clockOf('9:05'), '09:05:00');
      expect(clockOf('9:5'), isNull);
    });

    test('the time is kept in the state and cleared with null', () {
      s.dispatchSync(SetAroundAction('11:52:04'));
      expect(s.state.system.around, '11:52:04');
      s.dispatchSync(SetAroundAction(null));
      expect(s.state.system.around, isNull);
    });
  });
}
