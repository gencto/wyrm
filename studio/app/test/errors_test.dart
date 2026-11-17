import 'dart:io';

import 'package:app/common/app_store.dart';
import 'package:app/common/forms.dart';
import 'package:app/common/studio_version.dart';
import 'package:app/dialogs/error_dialogs.dart';
import 'package:app/dialogs/exception_dialog.dart';
import 'package:app/errors.dart';
import 'package:app/faults.dart';
import 'package:app/run_env.dart' show devicePrompts;
import 'package:app/start_fault_app.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/trigger_block_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/store.dart';
import 'package:business/redux/system/actions/aim_log_action.dart';
import 'package:business/redux/system/actions/set_around_action.dart';
import 'package:business/wyrm/calls.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/mappers/log_line_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart' hide Action, ErrorHint;
import 'package:models/error_call.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_subject.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_error.dart';
import 'package:models/system_tab.dart';
import 'package:storage/storage.dart';
import 'package:ui/alerts/panel_fault.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

StudioError _refused(
  Status status,
  String message, {
  String key = 'wy/plant/dataflows/pump-control',
  String call = 'deploy',
  String? thing,
  bool write = true,
}) => wordError(
  refusalOf(
    WyrmException.of(status, message),
    key: key,
    // the wire name, read as an action's is
    call: ErrorCall.ofWire(call),
    thing: thing,
    write: write,
  ).copyWith(id: 1, at: DateTime(2026, 11, 10, 11, 52, 4)),
);

/// Fails as the broker would refuse it.
class _Refused extends Action {
  _Refused(this.code, this.message, {this.name = 'deploy', super.quiet});

  final Status code;
  final String message;
  final String name;

  @override
  Action again() => _Refused(code, message, name: name);

  @override
  Future<AppState?> reduce() => call(
    ErrorCall.ofWire(name),
    'wy/plant/dataflows/$name-it',
    () async => throw WyrmException.of(code, message),
    write: true,
  );
}

Store<AppState> _store() => Store<AppState>(
  initialState: AppState.initial(),
  dependencies: (s) => AppDependencies(
    s,
    InMemoryKeyValueStorage(),
    wording: wordError,
    prompts: devicePrompts,
  ),
);

/// The app's own arrangement: the dialog host above the Navigator, which
/// it reaches through `NavigateAction.navigatorKey` (as `run_env` sets it).
Widget _app(Store<AppState> store) {
  final navigator = GlobalKey<NavigatorState>();
  NavigateAction.setNavigatorKey(navigator);
  return StoreProvider<AppState>(
    store: store,
    child: AppStore(
      store: store,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: darkTheme(),
        localizationsDelegates: const [S.delegate],
        home: const Scaffold(body: Text('the screen')),
        builder: (context, child) => ExceptionDialog<AppState>(
          onShowUserExceptionDialog: showUserException,
          child: child!,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => S.load(const Locale('en')));

  group('the title says what did not happen (errors.md §7)', () {
    test('one pattern per kind, with its object', () {
      expect(
        _refused(Status.permissionDenied, 'needs config').title,
        'You can’t deploy pump-control',
      );
      expect(
        _refused(
          Status.timeout,
          '',
          key: 'wy/edge/downstream/modbus/plc1/t2',
          call: 'set',
        ).title,
        'edge did not answer',
      );
      expect(
        _refused(Status.invalidParameter, 'poll_rate: 0', call: 'edit').title,
        'The broker refused these parameters',
      );
      expect(
        _refused(Status.outOfRange, 'too big', call: 'set').title,
        'The broker refused this value',
      );
      expect(
        _refused(
          Status.busy,
          'rebuilding',
          key: 'wy/plant/sys/links',
          call: 'install_repo',
        ).title,
        'plant is busy, the install did not start',
      );
      expect(
        _refused(Status.notFound, 'No node', call: 'get_def').title,
        'pump-control is not there anymore',
      );
      expect(
        _refused(Status.notSupported, '', call: 'trigger').title,
        'pump-control does not support trigger',
      );
      expect(
        _refused(
          Status.internalError,
          'unpack failed',
          key: 'wy/plant/sys/links',
          call: 'install_repo',
          thing: 'modbus 0.4.2',
        ).title,
        'Installing modbus 0.4.2 failed on plant',
      );
      expect(
        wordError(
          faultOf(
            StateError('x'),
            null,
            step: const .named('load flow'),
          ),
        ).title,
        'Studio could not finish “load flow”',
      );
    });

    test('a link that is not connected is named, not its site', () {
      expect(
        _refused(
          Status.disconnected,
          'wy/edge/downstream/modbus is not connected',
          key: 'wy/edge/downstream/modbus/plc1',
          call: 'ping',
        ).title,
        'modbus did not answer',
      );
      expect(
        _refused(
          Status.disconnected,
          'peer down',
          key: 'wy/edge/sys/links',
          call: 'list',
        ).title,
        'edge did not answer',
      );
    });

    test('an action Studio does not know reads with its own name', () {
      expect(
        _refused(
          Status.permissionDenied,
          '',
          key: 'wy/plant/downstream/mock',
          call: 'count',
        ).title,
        'You can’t run count on mock',
      );
    });

    test('never "Error" or "Something went wrong"', () {
      for (final st in Status.values) {
        final t = _refused(st, '').title;
        expect(t, isNot('Error'));
        expect(t.toLowerCase(), isNot(contains('something went wrong')));
        expect(t, isNotEmpty);
      }
      final fault = wordError(faultOf(Exception('x'), null));
      expect(
        fault.title.toLowerCase(),
        isNot(contains('something went wrong')),
      );
      expect(fault.message, contains('a fault in Studio'));
      expect(fault.message, isNot(contains('Exception')));
    });

    test('a refused Run the broker said nothing of reads why; the '
        "broker's words win", () {
      StudioError run(Status st, String m) => wordError(
        refusalOf(
          WyrmException.of(st, m),
          key: 'wy/plant/dataflows/line',
          call: const .known(.trigger),
        ).copyWith(hint: m.isEmpty ? triggerHintOf(StatusCode.of(st)) : null),
      );
      expect(run(Status.permissionDenied, '').message, contains('needs write'));
      expect(run(Status.notSupported, '').message, 'The flow is not running.');
      expect(run(Status.notFound, '').message, contains('no trigger action'));
      expect(
        run(Status.invalidParameter, '').message,
        'This block cannot be run by hand.',
      );
      expect(run(Status.busy, 'queue full').message, 'queue full');
    });

    test('a value whose meta names no level is not staged; the user reads '
        'why, in their language', () async {
      Future<StudioError> refused() async {
        final store = _store();
        await store.dispatchAndWait(
          StageValueAction('wy/plant/downstream/modbus/plc1/t2', 21.5),
        );
        expect(store.state.changes.table, isEmpty);
        return store.state.problems.items.single;
      }

      final en = await refused();
      expect(en.hint, const ErrorHint.notSettable());
      expect(en.title, 't2 does not support set');
      expect(
        en.message,
        'Its meta names no level it can be set at, so nothing was staged.',
      );

      await S.load(const Locale('uk'));
      addTearDown(() => S.load(const Locale('en')));
      final uk = await refused();
      expect(uk.title, 't2 не підтримує set');
      expect(
        uk.message,
        'Його meta не називає рівня, на якому значення можна записати, '
        'тому нічого не підготовлено.',
      );
    });

    test('what Studio did on its own reads as what stopped', () {
      final sub = refusalOf(
        WyrmException.of(Status.timeout, ''),
        key: 'wy/plant/downstream/modbus/plc1/t2',
        call: const .known(.subscribe),
      ).copyWith(quiet: true);
      expect(wordError(sub).title, 'Reading t2 failed');
      expect(
        wordError(sub.copyWith(stream: 'edge')).title,
        'Live values from edge stopped',
      );
      expect(
        wordError(sub.copyWith(call: const .known(.history))).title,
        'History of t2 unavailable',
      );
    });

    test(
      "in Ukrainian too; the broker's message is never translated",
      () async {
        await S.load(const Locale('uk'));
        addTearDown(() => S.load(const Locale('en')));
        final e = _refused(
          Status.permissionDenied,
          'needs config on dataflows',
        );
        expect(e.title, 'Ви не можете розгорнути pump-control');
        expect(errorDialogVm(e).said, 'needs config on dataflows');
        expect(errorDialogVm(e).primary, 'OK');
      },
    );
  });

  group('the dialog of a kind (errors.md §1, §3)', () {
    test('main buttons', () {
      ErrorAction of(StudioError e, {bool readOnly = false}) =>
          errorPrimary(e, readOnly: readOnly);
      StudioError again(StudioError e) => e.copyWith(
        retry: Object.new,
        reload: Object.new,
      );

      expect(of(_refused(Status.permissionDenied, '')), ErrorAction.ok);
      expect(of(again(_refused(Status.timeout, ''))), ErrorAction.retry);
      expect(
        of(_refused(Status.timeout, '')),
        ErrorAction.ok,
        reason: 'nothing to repeat',
      );
      expect(of(_refused(Status.invalidParameter, '')), ErrorAction.form);
      expect(of(again(_refused(Status.busy, ''))), ErrorAction.retry);
      expect(of(again(_refused(Status.notFound, ''))), ErrorAction.refresh);
      expect(of(_refused(Status.internalError, '')), ErrorAction.log);
      expect(of(wordError(faultOf(StateError('x'), null))), ErrorAction.ok);
      // From Problems: a write is not sent again.
      expect(
        of(again(_refused(Status.timeout, '')), readOnly: true),
        ErrorAction.ok,
      );
      expect(
        of(again(_refused(Status.timeout, '', write: false)), readOnly: true),
        ErrorAction.retry,
      );
    });

    test('rights: OK and See my access; the status with its code in '
        'Details', () {
      final vm = errorDialogVm(
        _refused(Status.permissionDenied, 'Deploying needs config.'),
        user: 'olena',
        role: 'operator',
        gateway: 'https://plant.local:8445',
      );
      expect(vm.primary, 'OK');
      expect(vm.secondary, 'See my access');
      expect(vm.saidLabel, 'The broker said');
      expect(vm.said, 'Deploying needs config.');
      expect(vm.where, 'wy/plant/dataflows/pump-control › deploy');
      expect(vm.chip, 'permission_denied');
      expect(vm.detailsOpen, isFalse);
      expect(vm.copy, 'Copy details');
      expect(
        {for (final r in vm.details) r.label: r.value},
        {
          'Status': 'permission_denied (0x21)',
          'Call': 'deploy on wy/plant/dataflows/pump-control',
          'Site': 'plant',
          'As': 'olena (operator)',
          'Gateway': 'https://plant.local:8445',
          'Time': '2026-11-10 11:52:04 (local)',
        },
      );
      expect(vm.advice.last, contains('operator'));
    });

    test('a timeout on a write warns; on a read it does not; with no '
        'message Studio says one sentence', () {
      final write = errorDialogVm(
        _refused(Status.timeout, '', call: 'set').copyWith(retry: Object.new),
      );
      expect(write.note, contains('may still have been applied'));
      expect(write.saidLabel, 'Studio waited');
      expect(write.said, 'No answer from the broker at plant.');
      expect(write.primary, 'Try again');
      expect(write.secondary, 'Close');
      expect(write.countdown, isNull, reason: 'never by itself');

      final read = errorDialogVm(
        _refused(Status.timeout, '', call: 'list', write: false),
      );
      expect(read.note, isNull);
    });

    test('input: Back to the form, and the field the broker named', () {
      final vm = errorDialogVm(
        _refused(Status.invalidParameter, 'poll_rate: 0 is below 100 ms.'),
      );
      expect(vm.primary, 'Back to the form');
      expect(vm.secondary, isNull);
      expect(vm.advice.single, contains('poll_rate'));
    });

    test('busy counts 4 s down, then tries again by itself', () {
      final vm = errorDialogVm(
        _refused(Status.busy, 'rebuilding').copyWith(retry: Object.new),
      );
      expect(vm.countdown, busyWait);
      expect(vm.countdownLabel!(4), 'Try again in 4 s');
      expect(vm.primary, 'Try again');
      // Opened from Problems it does not.
      expect(
        errorDialogVm(
          _refused(Status.busy, '').copyWith(retry: Object.new),
          readOnly: true,
        ).countdown,
        isNull,
      );
    });

    test('broker: Open the log, Details open', () {
      final vm = errorDialogVm(_refused(Status.internalError, 'unpack failed'));
      expect(vm.primary, 'Open the log');
      expect(vm.secondary, 'Close');
      expect(vm.detailsOpen, isTrue);
      expect(vm.advice.single, contains('11:52'));
    });

    test('studio: What happened, Copy report, the report rows; no stack '
        'on screen', () {
      StackTrace? stack;
      try {
        throw const FormatException('Unexpected character', 'secret', 3);
      } on FormatException catch (_, st) {
        stack = st;
      }
      final e = wordError(
        faultOf(
          const FormatException('Unexpected character', 'secret', 3),
          stack,
          step: const .named('load flow'),
        ).copyWith(at: DateTime(2026, 11, 10, 11, 52, 4)),
      );
      final vm = errorDialogVm(e);
      expect(vm.saidLabel, 'What happened');
      expect(vm.primary, 'OK');
      expect(vm.secondary, isNull);
      expect(vm.copy, 'Copy report');
      expect(vm.chip, 'studio · FormatException');
      expect(vm.detailsOpen, isTrue);
      final rows = {for (final r in vm.details) r.label: r.value};
      expect(rows['Error'], contains('Unexpected character'));
      expect(rows['Report'], 'the stack trace is in the copied report only');
      expect(rows.values.join(), isNot(contains('#0')));
      expect(rows.values.join(), isNot(contains('secret')));
      expect(rows['Studio'], contains(studioVersion));
    });

    test('a plain UserException: the same card, studio styling, OK', () {
      final e = wordError(
        studioExceptionOf(
          const UserException('No network', reason: 'Check the cable.'),
          null,
        ).error,
      );
      final vm = errorDialogVm(e);
      expect(vm.title, 'No network');
      expect(vm.said, 'Check the cable.');
      expect(vm.tone, errorToneOf(ErrorKind.studio));
      expect(vm.primary, 'OK');
      expect(vm.copy, 'Copy details');
    });
  });

  group('the dialog replaces the Material AlertDialog (errors.md §3)', () {
    testWidgets('a refused call the user started shows it, once, and is '
        'marked in Problems', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));

      await store.dispatchAndWait(
        _Refused(Status.permissionDenied, 'needs config on dataflows'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ErrorDialog), findsOneWidget);
      expect(find.text('You can’t deploy deploy-it'), findsOneWidget);
      expect(
        find.text('wy/plant/dataflows/deploy-it › deploy'),
        findsOneWidget,
      );
      expect(find.text('needs config on dataflows'), findsOneWidget);
      expect(store.state.problems.items.single.shown, isTrue);

      // A second one while it is open: Problems only, the counter rises.
      await store.dispatchAndWait(
        _Refused(Status.notFound, 'gone', name: 'remove'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorDialog), findsOneWidget);
      expect(find.text('You can’t deploy deploy-it'), findsOneWidget);
      expect(store.state.problems.items.length, 2);
      expect(store.state.problems.items.first.shown, isFalse);
      expect(store.state.problems.unread, 2);

      // Esc closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorDialog), findsNothing);
      expect(errorDialogOpen, isFalse);
    });

    testWidgets('Try again closes the dialog and dispatches the call again', (
      tester,
    ) async {
      final store = _store();
      await tester.pumpWidget(_app(store));
      await store.dispatchAndWait(_Refused(Status.timeout, ''));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('may still have been applied'),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // The same failure came again: its line was replaced, and it is the
      // dialog once more.
      expect(store.state.problems.items.length, 1);
      expect(find.byType(ErrorDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorDialog), findsNothing);
    });

    testWidgets('a quiet failure opens no dialog', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));

      await store.dispatchAndWait(
        _Refused(Status.timeout, 'slow', quiet: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorDialog), findsNothing);
      expect(store.state.problems.toasts.length, 1);
      expect(
        errorToastVm(store.state.problems.items.single).line,
        'timeout: slow',
      );
    });

    testWidgets('Copy details puts no value on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final store = _store();
      await tester.pumpWidget(_app(store));
      await store.dispatchAndWait(
        _Refused(
          Status.invalidParameter,
          'password: hunter2-very-secret is too short',
          name: 'set',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy details'));
      await tester.pump();

      expect(copied, contains('invalid_parameter (0x23)'));
      expect(copied, contains('wy/plant/dataflows/set-it › set'));
      expect(copied, isNot(contains('hunter2')));
      expect(
        store.state.problems.notices.single.kind,
        NoticeKind.detailsCopied,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  });

  group('what Studio itself found wrong is said by the app', () {
    StudioError hinted(ErrorHint h) =>
        wordError(StudioError(kind: ErrorKind.studio, hint: h));

    test('business names the case; the words keep its data', () {
      expect(
        hinted(const ErrorHint.noAssistant()).message,
        'There is no assistant link on this site.',
      );
      expect(
        hinted(
          const ErrorHint.taskRecordInvalid(
            task: 't-7',
            field: 'plan[2].key',
            reason: 'missing',
          ),
        ).message,
        'The record of task t-7 is not one Studio reads: plan[2].key: '
        'missing.',
      );
      expect(
        hinted(
          ErrorHint.profileUnknownKey(key: 'unit', known: ['type', 'is'].lock),
        ).message,
        'Unknown key "unit" (known: type, is).',
      );
      expect(
        hinted(
          const ErrorHint.backupDigestMismatch(got: 'aa', expected: 'bb'),
        ).message,
        contains('SHA-256 aa, the broker says bb'),
      );
      expect(
        hinted(const ErrorHint.rangeTooBig()).message,
        S.current.rangeTooBig,
      );
    });

    test("in Ukrainian too, and the broker's own words win", () async {
      final en = hinted(const ErrorHint.assistantNoTask()).message;
      await S.load(const Locale('uk'));
      addTearDown(() => S.load(const Locale('en')));
      final uk = hinted(const ErrorHint.assistantNoTask()).message;
      expect(uk, isNotEmpty);
      expect(uk, isNot(en));
      expect(
        wordError(
          const StudioError(
            kind: ErrorKind.broker,
            message: 'said by the link',
            hint: ErrorHint.notConnected(),
          ),
        ).message,
        'said by the link',
      );
    });

    test('a subject Studio names is worded; a name from the broker is not', () {
      StudioError of(ErrorSubject s, {String? thing}) => _refused(
        Status.permissionDenied,
        'no',
        key: 'wy/plant/x',
        call: 'ask',
      ).copyWith(title: '', subject: s, thing: thing);
      expect(
        wordError(of(ErrorSubject.assistant)).title,
        'You can’t run ask on assistant',
      );
      expect(
        wordError(of(ErrorSubject.device, thing: '7')).title,
        'You can’t run ask on device 7',
      );
    });
  });

  group('Copy details (errors.md §3)', () {
    const ctx = DetailsContext(
      user: 'olena',
      role: 'operator',
      gateway: 'https://olena:gw-pass@plant.local:8445',
      studio: '1.0 (macOS 15.1)',
    );

    test('holds the title, key › call, status with code, message, site, '
        'user, gateway, time and Studio', () {
      const key = 'wy/central/sys/links/modbus';
      final e = _refused(
        Status.permissionDenied,
        'needs config on sys/links',
        key: key,
        call: 'start',
      );

      final text = detailsText(e, ctx);

      expect(text, contains(e.title));
      expect(text, contains('$key › start'));
      expect(text, contains('Status: permission_denied (0x21)'));
      expect(text, contains('Message: needs config on sys/links'));
      expect(text, contains('Site: central'));
      expect(text, contains('As: olena (operator)'));
      expect(text, contains('Gateway: https://plant.local:8445'));
      expect(text, contains('Time: 2026-11-10 11:52:04 (local)'));
      expect(text, contains('Studio: 1.0 (macOS 15.1)'));
    });

    test('never a value, an argument, a token or a password: a set of a '
        'secret field', () {
      const key = 'wy/central/downstream/mqtt/broker/password';
      const secret = 's3cr3t-Passw0rd';
      // The broker echoes what it was sent, as some drivers do.
      final e = _refused(
        Status.invalidParameter,
        'password: $secret is too short; token=eyJhbGciOiJIUzI1NiJ9.abc.def '
        'Bearer abcdefghijklmnop',
        key: key,
        call: 'set',
      );
      final text = detailsText(e, ctx, report: true);

      expect(e.kind, ErrorKind.input);
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(text, isNot(contains('abcdefghijklmnop')));
      expect(text, isNot(contains('gw-pass')));
      expect(text, contains('password: •••'));
    });

    test('Copy report adds the type, the first line and the stack', () {
      final e = wordError(
        faultOf(
          const FormatException('Unexpected character', 'pw=hunter2', 4),
          StackTrace.current,
          step: const .named('buggy'),
        ),
      );

      final short = detailsText(e, ctx);
      final full = detailsText(e, ctx, report: true);

      expect(short, contains('Error: FormatException: Unexpected character'));
      expect(short, isNot(contains('#0')));
      expect(full, contains('#0'));
      expect(full, isNot(contains('hunter2')));
    });

    test('in Ukrainian the labels are the Details rows', () async {
      await S.load(const Locale('uk'));
      addTearDown(() => S.load(const Locale('en')));
      final text = detailsText(
        _refused(Status.timeout, '', key: 'wy/central/sys', call: 'list'),
        ctx,
      );
      expect(text, contains('${S.current.errRowSite}: central'));
      expect(text, isNot(contains('Site: ')));
    });
  });

  group('Back to the form (errors.md §3)', () {
    test("what a refusal says to the form: the broker's words and the "
        'field they name', () async {
      final store = _store();
      final named = await store.dispatchAndWait(
        _Refused(
          Status.invalidParameter,
          'poll_rate: 0 is below the minimum of 100 ms.',
          name: 'edit',
        ),
      );
      final r = formRefusal(named)!;
      expect(r.field, 'poll_rate');
      expect(r.message, '0 is below the minimum of 100 ms.');
      // A parameter the form holds under another id.
      expect(
        formRefusal(named, fields: const {'poll_rate': 'poll'})!.field,
        'poll',
      );

      final unnamed = await store.dispatchAndWait(
        _Refused(Status.invalidParameter, 'The arguments do not fit.'),
      );
      expect(formRefusal(unnamed)!.field, isNull);
      expect(formRefusal(unnamed)!.message, 'The arguments do not fit.');
      final other = await store.dispatchAndWait(
        _Refused(Status.permissionDenied, 'poll_rate: no'),
      );
      expect(formRefusal(other), isNull, reason: 'only an input refusal');
    });

    testWidgets('a form in a dialog: the error dialog closes onto the form '
        'with its values, the field marked and in focus', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));
      final context = tester.element(find.text('the screen'));
      var closed = false;
      showDialog<void>(
        context: context,
        builder: (dialog) => PanelDialog(
          title: 'Edit plc1',
          child: ActionForm(
            fields: [
              ParamFieldVm(
                id: 'host',
                label: 'Host',
                kind: ParamKind.text,
                value: '10.0.0.7',
                onChanged: (_) {},
              ),
              ParamFieldVm(
                id: 'poll_rate',
                label: 'Poll rate',
                kind: ParamKind.number,
                value: 1000,
                onChanged: (_) {},
              ),
            ],
            submit: 'Save',
            onSubmit: (v) => sendForm(
              store.dispatchAndWait(
                _Refused(
                  Status.invalidParameter,
                  'poll_rate: ${v['poll_rate']} is below the minimum of '
                  '100 ms.',
                  name: 'edit',
                ),
              ),
              onOk: () => closed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '10.0.0.7'),
        '10.0.0.9',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '1000'), '5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The error dialog is over the form and offers the way back.
      expect(find.byType(ErrorDialog), findsOneWidget);
      expect(find.text('Back to the form'), findsOneWidget);
      await tester.tap(find.text('Back to the form'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorDialog), findsNothing);
      expect(closed, isFalse);
      expect(find.text('Edit plc1'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '10.0.0.9'), findsOneWidget);
      expect(find.text('5 is below the minimum of 100 ms.'), findsOneWidget);
      final field = find.widgetWithText(TextFormField, '5');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
    });
  });

  group('Open the log (errors.md §3)', () {
    testWidgets("System › Log gets the error's time, on the rows' clock", (
      tester,
    ) async {
      final store = _store();
      await tester.pumpWidget(_app(store));
      // A time typed before: the error's replaces it.
      store.dispatchSync(SetAroundAction('01:00:00'));
      await store.dispatchAndWait(
        _Refused(Status.internalError, 'unpack: wyrm_link 3 is newer'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open the log'), findsOneWidget);
      final e = store.state.problems.items.single;
      final at = e.at!;
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // What the button does before it navigates (this harness has no
      // router): one action, the tab and its time in one state.
      store.dispatchSync(AimLogAction(e.at));

      expect(store.state.system.tab, SystemTab.log);
      expect(store.state.system.around, logClockOf(at));
      final utc = at.toUtc();
      expect(
        secondOfDay(store.state.system.around!),
        utc.hour * 3600 + utc.minute * 60 + utc.second,
      );
    });
  });

  group('a part failed to draw (errors.md §5)', () {
    testWidgets('an uncaught fault is a quiet studio problem, never a '
        'dialog', (tester) async {
      final store = _store();
      final builder = ErrorWidget.builder;
      final onError = FlutterError.onError;
      final platform = tester.binding.platformDispatcher.onError;
      // Back before the test ends: the binding checks its own handler.
      void restore() {
        ErrorWidget.builder = builder;
        FlutterError.onError = onError;
        tester.binding.platformDispatcher.onError = platform;
        PanelFault.copyReport = null;
      }

      FlutterError.onError = (_) {};
      installFaultHooks(store, cardInDebug: true);
      await tester.pumpWidget(_app(store));

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: RangeError.index(3, const [1, 2, 3]),
          library: 'widgets library',
        ),
      );
      await tester.pumpAndSettle();

      final e = store.state.problems.items.single;
      expect(e.kind, ErrorKind.studio);
      expect(e.quiet, isTrue);
      expect(e.report!.type, 'IndexError');
      expect(e.title, 'Studio hit a fault in the background');
      expect(find.byType(ErrorDialog), findsNothing);
      expect(ErrorWidget.builder, PanelFault.builder);
      restore();
    });
  });

  group('Studio cannot start (errors.md §6)', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('wyrm-studio-'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('an unreadable settings file shows the start screen; fresh '
        'settings keep the old file and start again', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final file = File('${dir.path}/$settingsFile');
      late StorageFault fault;
      await tester.runAsync(() async {
        file.writeAsStringSync('not a database {{{');
        try {
          await openSettings(directory: dir.path);
          fail('the settings opened');
        } on StorageFault catch (f) {
          fault = f;
        }
      });
      var started = 0;

      await tester.pumpWidget(
        StartFaultApp(
          fault: fault,
          onFresh: () async => started++,
          onQuit: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Studio could not start'), findsOneWidget);
      expect(
        find.textContaining('Your brokers are not affected'),
        findsOneWidget,
      );
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(find.textContaining(settingsFile), findsWidgets);
      expect(find.textContaining('$settingsFile.broken'), findsOneWidget);
      expect(file.readAsStringSync(), 'not a database {{{', reason: 'kept');

      await tester.runAsync(() async {
        await tester.tap(find.text('Start with fresh settings'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(started, 1);
      expect(file.existsSync(), isFalse);
      expect(
        File('${file.path}.broken').readAsStringSync(),
        'not a database {{{',
      );
      // And Studio's settings now open.
      await tester.runAsync(() async {
        final settings = await openSettings(directory: dir.path);
        await settings.put('locale', 'uk');
        expect(await settings.get<String>('locale'), 'uk');
      });
    });
  });
}
