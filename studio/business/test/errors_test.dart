import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:business/environment.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/start_link_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/problems/actions/add_problem_action.dart';
import 'package:business/redux/problems/actions/clear_problems_action.dart';
import 'package:business/redux/problems/actions/dismiss_toast_action.dart';
import 'package:business/redux/problems/actions/mark_problem_shown_action.dart';
import 'package:business/redux/problems/actions/open_problems_action.dart';
import 'package:business/redux/problems/actions/resolve_stream_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/redux/store.dart';
import 'package:business/wyrm/calls.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/error_kind.dart';
import 'package:models/live_value.dart';

import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// Writes [value] to [key]: a `set`, as a screen would send it.
class _SetAction extends Action {
  _SetAction(this.key, this.value);

  final String key;
  final String value;

  @override
  Action again() => _SetAction(key, value);

  @override
  Future<AppState?> reduce() async {
    await call(
      'set',
      key,
      () => deps.wyrm.set(key, VStr(value)),
      write: true,
    );
    return null;
  }
}

/// Throws what a bug would.
class _BuggyAction extends Action {
  @override
  AppState? reduce() =>
      throw const FormatException('Unexpected character', 'pw=hunter2', 4);
}

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

  StudioError failed(ActionStatus st) =>
      (st.wrappedError! as StudioException).error;

  group('status → kind (spec 04)', () {
    const expected = {
      Status.permissionDenied: ErrorKind.rights,
      Status.timeout: ErrorKind.reach,
      Status.disconnected: ErrorKind.reach,
      Status.notAvailable: ErrorKind.reach,
      Status.closed: ErrorKind.reach,
      Status.invalidParameter: ErrorKind.input,
      Status.invalidMessage: ErrorKind.input,
      Status.outOfRange: ErrorKind.input,
      Status.busy: ErrorKind.busy,
      Status.rateLimited: ErrorKind.busy,
      Status.resourceExhausted: ErrorKind.busy,
      Status.notFound: ErrorKind.gone,
      Status.notSupported: ErrorKind.gone,
      Status.internalError: ErrorKind.broker,
      // Never failures; one thrown all the same is the broker's fault.
      Status.ok: ErrorKind.broker,
      Status.initializing: ErrorKind.broker,
      Status.refreshed: ErrorKind.broker,
    };

    test('every status of the table has a kind', () {
      expect(expected.keys.toSet(), Status.values.toSet());
      for (final MapEntry(key: status, value: kind) in expected.entries) {
        expect(kindOf(StatusCode.of(status)), kind, reason: status.wireName);
      }
    });

    test("a user-defined and an unknown code are the broker's", () {
      expect(kindOf(const StatusCode(userStatusFirst)), ErrorKind.broker);
      expect(kindOf(const StatusCode(userStatusLast)), ErrorKind.broker);
      expect(kindOf(const StatusCode(0x3F)), ErrorKind.broker);
      expect(kindOf(const StatusCode(0xEE)), ErrorKind.broker);
    });

    test('no status at all is a fault in Studio', () {
      expect(kindOf(null), ErrorKind.studio);
    });

    test('Details show the name with the code', () {
      expect(
        statusLine(StatusCode.of(Status.permissionDenied)),
        'permission_denied (0x21)',
      );
      expect(
        statusLine(StatusCode.of(Status.rateLimited)),
        'rate_limited (0x2A)',
      );
      expect(statusLine(const StatusCode(0x41)), 'user_65 (0x41)');
    });
  });

  group('one model for every failure', () {
    test(
      'a refusal keeps its status as data, with the key and the call',
      () async {
        api.errors['wy/central/sys/links ▸ x'] = WyrmException.of(
          Status.busy,
          '',
        );
        // No children answer for sys/links: the fake says not_found.
        final st = await s.dispatchAndWait(RetrieveLinksAction());

        final e = failed(st);
        expect(e.status, StatusCode.of(Status.notFound));
        expect(e.kind, ErrorKind.gone);
        expect(e.key, 'wy/central/sys/links');
        expect(e.call, 'list');
        expect(e.where, 'wy/central/sys/links › list');
        expect(e.site, 'central');
        expect(e.write, isFalse);
        expect(
          e.message,
          isNot(contains('not_found:')),
          reason: 'not flattened',
        );
        expect(e.id, greaterThan(0));
        expect(e.at, isNotNull);
        expect(e.title, isNotEmpty);
      },
    );

    test('a timeout on a write is marked: it may have been applied', () async {
      const key = 'wy/central/sys/links/modbus';
      api.errors['$key ▸ start'] = WyrmException.of(Status.timeout, '');

      final e = failed(await s.dispatchAndWait(StartLinkAction('modbus')));

      expect(e.kind, ErrorKind.reach);
      expect(e.write, isTrue);
      expect(e.call, 'start');
    });

    test('a timeout on a read is not', () async {
      api.errors['wy/central/sys/links'] = WyrmException.of(Status.timeout, '');

      final e = failed(await s.dispatchAndWait(RetrieveLinksAction()));

      expect(e.kind, ErrorKind.reach);
      expect(e.write, isFalse);
    });

    test(
      'an answer {success: false} is a broker error with its message',
      () async {
        const key = 'wy/central/downstream/mock';
        api.invokes['$key ▸ count'] = [
          Value.from({'success': false, 'message': 'n must be positive'}),
        ];

        final e = failed(
          await s.dispatchAndWait(InvokeNodeAction(key, 'count')),
        );

        expect(e.kind, ErrorKind.broker);
        expect(e.status, isNull);
        expect(e.message, 'n must be positive');
        expect(e.where, '$key › count');
      },
    );

    test('invalid_parameter names its field when the broker does', () async {
      const key = 'wy/central/downstream/modbus/plc1';
      api.errors['$key ▸ edit'] = WyrmException.of(
        Status.invalidParameter,
        'poll_rate: 0 is below the minimum of 100 ms.',
      );

      final e = failed(
        await s.dispatchAndWait(
          InvokeNodeAction(key, 'edit', {'poll_rate': 0}),
        ),
      );

      expect(e.kind, ErrorKind.input);
      expect(e.field, 'poll_rate');
      expect(fieldOf('The value is out of range.'), isNull);
      expect(fieldOf('n: -1 is out of range'), 'n');
    });

    test('anything else is a fault in Studio with a report', () async {
      final e = failed(await s.dispatchAndWait(_BuggyAction()));

      expect(e.kind, ErrorKind.studio);
      expect(e.status, isNull);
      expect(e.report!.type, 'FormatException');
      expect(e.report!.line, contains('Unexpected character'));
      expect(e.report!.line, contains('offset 4'));
      expect(e.report!.line, isNot(contains('hunter2')), reason: 'no source');
      expect(e.report!.stack, isNotEmpty);
      expect(e.call, 'buggy');
    });

    test('a plain UserException keeps its title and reason', () {
      final x = studioExceptionOf(
        const UserException('No network', reason: 'Check the cable.'),
        null,
      );
      expect(x.error.kind, ErrorKind.studio);
      expect(x.error.title, 'No network');
      expect(x.error.message, 'Check the cable.');
      expect(x.error.report, isNull);
    });

    test('it is a UserException: the store queues it for the dialog', () async {
      await s.dispatchAndWait(RetrieveLinksAction());
      expect(s.getAndRemoveFirstError(), isA<StudioException>());
    });
  });

  group('primary actions', () {
    test('Try again dispatches the same call again', () async {
      const key = 'wy/central/sys/links/modbus';
      api.errors['$key ▸ start'] = WyrmException.of(Status.busy, 'rebuilding');
      final e = failed(await s.dispatchAndWait(StartLinkAction('modbus')));
      expect(e.retry, isNotNull);
      final before = api.calls.length;
      api.errors.clear();
      api.invokes['$key ▸ start'] = [];

      await s.dispatchAndWait(RetryProblemAction(e.id));

      expect(api.calls.length, before + 1);
      expect(api.calls.last.toString(), contains('$key ▸ start'));
    });

    test('Refresh dispatches the load action of the screen', () async {
      const key = 'wy/central/sys/links/gone';
      final e = failed(await s.dispatchAndWait(StartLinkAction('gone')));
      expect(e.kind, ErrorKind.gone);
      expect(e.reload, isNotNull);
      api.children_['wy/central/sys/links'] = [];
      final before = api.calls.length;

      await s.dispatchAndWait(RetryProblemAction(e.id, refresh: true));

      expect(
        [for (final c in api.calls.skip(before)) '$c'],
        contains(contains('wy/central/sys/links')),
      );
      expect(key, isNotEmpty);
    });

    test('an action that cannot be repeated offers none', () async {
      final e = failed(await s.dispatchAndWait(_BuggyAction()));
      expect(e.retry, isNull);
      expect(e.reload, isNull);
    });
  });

  group('problems', () {
    StudioError err(
      String key, {
      Status st = Status.timeout,
      bool quiet = true,
    }) => refusalOf(
      WyrmException.of(st, 'm'),
      key: key,
      call: 'subscribe',
    ).copyWith(quiet: quiet);

    test(
      'every failure is added, newest first; a dialog one has no toast',
      () async {
        await s.dispatchAndWait(RetrieveLinksAction());
        s.dispatchSync(AddProblemAction(err('wy/central/a')));

        final p = s.state.problems;
        expect(p.items.length, 2);
        expect(p.items.first.key, 'wy/central/a');
        expect(p.unread, 2);
        expect(p.toasts, [p.items.first.id], reason: 'only the quiet one');
      },
    );

    test('a quiet action fails without a dialog and with a toast', () async {
      final st = await s.dispatchAndWait(RetrieveLinksAction(quiet: true));

      final x = st.wrappedError! as StudioException;
      expect(x.ifOpenDialog, isFalse);
      expect(x.error.quiet, isTrue);
      expect(s.getAndRemoveFirstError(), isNull);
      expect(s.state.problems.toasts, [x.error.id]);
    });

    test('the same failure again replaces its line and its toast', () {
      s
        ..dispatchSync(AddProblemAction(err('wy/central/a')))
        ..dispatchSync(AddProblemAction(err('wy/central/b')))
        ..dispatchSync(AddProblemAction(err('wy/central/a')));

      final p = s.state.problems;
      expect(
        [for (final e in p.items) e.key],
        ['wy/central/a', 'wy/central/b'],
      );
      expect(p.unread, 2);
      expect(p.toasts.length, 2);
      expect(p.toasts.last, p.items.first.id);
    });

    test('another status on the same key is another line', () {
      s
        ..dispatchSync(AddProblemAction(err('wy/central/a')))
        ..dispatchSync(
          AddProblemAction(err('wy/central/a', st: Status.notFound)),
        );
      expect(s.state.problems.items.length, 2);
    });

    test('at most 200 are kept', () {
      for (var i = 0; i < AddProblemAction.limit + 20; i++) {
        s.dispatchSync(AddProblemAction(err('wy/central/k$i')));
      }
      expect(s.state.problems.items.length, AddProblemAction.limit);
      expect(s.state.problems.items.first.key, 'wy/central/k219');
    });

    test('opening the drawer clears the counter; Clear all empties it', () {
      s
        ..dispatchSync(AddProblemAction(err('wy/central/a')))
        ..dispatchSync(OpenProblemsAction());
      expect(s.state.problems.open, isTrue);
      expect(s.state.problems.unread, 0);

      // While it is open a new one is seen at once.
      s.dispatchSync(AddProblemAction(err('wy/central/b')));
      expect(s.state.problems.unread, 0);

      s.dispatchSync(ClearProblemsAction());
      expect(s.state.problems.items, isEmpty);
      expect(s.state.problems.toasts, isEmpty);
    });

    test('one shown as a dialog is marked and loses its toast', () {
      s.dispatchSync(AddProblemAction(err('wy/central/a')));
      final id = s.state.problems.items.single.id;

      s.dispatchSync(MarkProblemShownAction(id));

      expect(s.state.problems.items.single.shown, isTrue);
      expect(s.state.problems.toasts, isEmpty);
    });

    test('a toast is dismissed; the problem stays', () {
      s.dispatchSync(AddProblemAction(err('wy/central/a')));
      final id = s.state.problems.items.single.id;

      s.dispatchSync(DismissToastAction(id));

      expect(s.state.problems.toasts, isEmpty);
      expect(s.state.problems.items.length, 1);
    });

    test('a notice is a toast of its own and no problem', () {
      s.dispatchSync(ShowNoticeAction('Copied'));
      expect(s.state.problems.notices.single.title, 'Copied');
      expect(s.state.problems.items, isEmpty);
      s.dispatchSync(DismissToastAction(s.state.problems.notices.single.id));
      expect(s.state.problems.notices, isEmpty);
    });

    test('the toast of a stream stays until its site is back', () {
      s
        ..dispatchSync(
          AddProblemAction(err('wy/edge/**').copyWith(stream: 'edge')),
        )
        ..dispatchSync(AddProblemAction(err('wy/central/a')))
        ..dispatchSync(ResolveStreamAction('plant'));
      expect(s.state.problems.toasts.length, 2);

      s.dispatchSync(ResolveStreamAction('edge'));

      expect(s.state.problems.toasts.length, 1);
      expect(s.state.problems.items.length, 2, reason: 'the line stays');
    });
  });

  group('reads Studio does on its own', () {
    test('a failed subscription marks the row and is a quiet problem; a '
        'value clears the mark', () async {
      const key = 'wy/central/downstream/modbus/plc1/t2';
      s.dispatchSync(WatchKeysAction([key]));
      api.subs[key]!.addError(WyrmException.of(Status.notFound, 'no node'));
      await Future<void>.delayed(Duration.zero);

      expect(s.state.live.failed[key], 'not_found');
      final e = s.state.problems.items.single;
      expect(e.quiet, isTrue);
      expect(e.where, '$key › subscribe');
      expect(s.state.problems.toasts, [e.id]);

      s.dispatchSync(
        SetLiveValuesAction({
          key: LiveValue(
            value: 1,

            time: DateTime.utc(2026),
          ),
        }),
      );
      expect(s.state.live.failed, isEmpty);
    });

    test('a stream that lost its broker is one problem of the site, and '
        'its toast stays', () async {
      const a = 'wy/central/downstream/modbus/plc1/t1';
      const b = 'wy/central/downstream/modbus/plc1/t2';
      s.dispatchSync(WatchKeysAction([a, b]));
      for (final k in [a, b]) {
        api.subs[k]!.addError(WyrmException.of(Status.disconnected, 'down'));
      }
      await Future<void>.delayed(Duration.zero);

      final e = s.state.problems.items.single;
      expect(e.stream, 'central');
      expect(e.key, 'wy/central/**');
      expect(s.state.live.failed.keys, containsAll([a, b]));
    });

    test('a key the user may not read is marked, without a toast', () async {
      const key = 'wy/central/downstream/modbus/plc1/secret';
      s.dispatchSync(WatchKeysAction([key]));
      api.subs[key]!.addError(WyrmException.of(Status.permissionDenied, ''));
      await Future<void>.delayed(Duration.zero);

      expect(s.state.live.failed[key], 'permission_denied');
      expect(s.state.problems.items.single.kind, ErrorKind.rights);
      expect(s.state.problems.toasts, isEmpty);
    });

    test('history that cannot be read is a quiet problem and a mark', () async {
      const key = 'wy/central/downstream/modbus/plc1/flow_rate';
      // The fake has no history for the key: not_found.
      api.errors['$key ▸ history'] = WyrmException.of(Status.notFound, 'x');
      final st = await s.dispatchAndWait(RetrieveHistoryAction(key));

      expect(st.isCompletedOk, isTrue, reason: 'no dialog for a chart');
      expect(s.state.nodes.historyFailed, 'not_found');
      final e = s.state.problems.items.single;
      expect(e.call, 'history');
      expect(e.quiet, isTrue);
      expect(e.retry, isNotNull);
    });
  });

  group('Copy details', () {
    const ctx = DetailsContext(
      user: 'olena',
      role: 'operator',
      gateway: 'https://olena:gw-pass@plant.local:8445',
      studio: '1.0 (macOS 15.1)',
    );

    test('holds the title, key › call, status with code, message, site, '
        'user, gateway, time and Studio', () async {
      const key = 'wy/central/sys/links/modbus';
      api.errors['$key ▸ start'] = WyrmException.of(
        Status.permissionDenied,
        'needs config on sys/links',
      );
      final e = failed(await s.dispatchAndWait(StartLinkAction('modbus')));

      final text = detailsText(e, ctx);

      expect(text, contains(e.title));
      expect(text, contains('$key › start'));
      expect(text, contains('Status: permission_denied (0x21)'));
      expect(text, contains('Message: needs config on sys/links'));
      expect(text, contains('Site: central'));
      expect(text, contains('As: olena (operator)'));
      expect(text, contains('Gateway: https://plant.local:8445'));
      expect(text, contains('Time: '));
      expect(text, contains('Studio: 1.0 (macOS 15.1)'));
    });

    test('never a value, an argument, a token or a password: a set of a '
        'secret field', () async {
      const key = 'wy/central/downstream/mqtt/broker/password';
      const secret = 's3cr3t-Passw0rd';
      // The broker echoes what it was sent, as some drivers do.
      api.errors[key] = WyrmException.of(
        Status.invalidParameter,
        'password: $secret is too short; token=eyJhbGciOiJIUzI1NiJ9.abc.def '
        'Bearer abcdefghijklmnop',
      );

      final e = failed(await s.dispatchAndWait(_SetAction(key, secret)));
      final text = detailsText(e, ctx, report: true);

      expect(e.kind, ErrorKind.input);
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(text, isNot(contains('abcdefghijklmnop')));
      expect(text, isNot(contains('gw-pass')));
      expect(text, contains('password: •••'));
      // The log line of the exception is as careful.
      expect('${StudioException(e)}', isNot(contains(secret)));
    });

    test('Copy report adds the type, the first line and the stack', () async {
      final e = failed(await s.dispatchAndWait(_BuggyAction()));

      final short = detailsText(e, ctx);
      final full = detailsText(e, ctx, report: true);

      expect(short, contains('Error: FormatException: Unexpected character'));
      expect(short, isNot(contains('#0')));
      expect(full, contains('#0'));
      expect(full, isNot(contains('hunter2')));
    });

    test('redact masks pairs, bearer tokens and long blobs, and leaves '
        'prose', () {
      expect(
        redact('poll_rate: 0 is below 100 ms'),
        'poll_rate: 0 is below 100 ms',
      );
      expect(redact('{"password":"abc"}'), '{"password":•••}');
      expect(redact('api_key = 12345'), 'api_key = •••');
      expect(
        redact('ptok ${'A' * 48}'),
        'ptok •••',
      );
    });
  });

  group("Studio's own settings", () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('wyrm-studio-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a file that is not a database is a StorageFault, and the file '
        'is left as it was', () async {
      final file = File('${dir.path}/$settingsFile')
        ..writeAsStringSync('this is not a sembast database\n{{{');

      await expectLater(
        createStore(await Environment.dev(), directory: dir.path),
        throwsA(
          isA<StorageFault>().having((f) => f.path, 'path', file.path),
        ),
      );
      expect(
        file.readAsStringSync(),
        startsWith('this is not a sembast database'),
        reason: 'not deleted, not rewritten',
      );
    });

    test('a file that cannot be opened is a StorageFault too', () async {
      // A directory where the file should be: opening it fails as a locked
      // or unreadable file does.
      Directory('${dir.path}/$settingsFile').createSync();

      await expectLater(
        openSettings(directory: dir.path),
        throwsA(isA<StorageFault>()),
      );
    });

    test('fresh settings keep the old file beside the new one', () async {
      final file = File('${dir.path}/$settingsFile')
        ..writeAsStringSync('garbage');

      final kept = await setAsideSettings(file.path);
      final settings = await openSettings(directory: dir.path);
      await settings.put('themeMode', 1);

      expect(kept, '${file.path}.broken');
      expect(File(kept).readAsStringSync(), 'garbage');
      expect(await settings.get<int>('themeMode'), 1);
    });
  });
}
