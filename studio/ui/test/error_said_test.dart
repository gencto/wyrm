import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_hint_words.dart';
import 'package:ui/dialogs/error_said.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/problems_drawer.dart';

/// An error is typed values until it is drawn (studio-rules §5): `ui` says
/// its title, its line, its toast and its Problems card in the language on
/// screen then, so one kept error reads in the language shown now.
void main() {
  setUp(() => S.load(const Locale('en')));

  const denied = ErrorSaid(
    id: 7,
    kind: ErrorKindTag.rights,
    icon: AppIcon.errRights,
    thing: ErrorThingVm.named('pump-control'),
    titleKind: ErrorTitleTag.rights,
    message: 'needs config on dataflows',
    status: 'permission_denied',
    statusLine: 'permission_denied (0x21)',
    key: 'wy/plant/dataflows/pump-control',
    call: ErrorCallVm('deploy', verb: ErrorVerb.deploy),
    site: 'plant',
    write: true,
  );

  test('one error reads in the language shown when it is drawn', () async {
    final toast = ToastVm.failure(denied);
    final card = ProblemVm.failure(denied);
    expect(denied.title, 'You can’t deploy pump-control');
    expect(toast.title, denied.title);
    expect(toast.line, 'permission_denied: needs config on dataflows');
    expect(card.said, toast.line);
    expect(toast.tone, Tone.warn);
    expect(denied.where, 'wy/plant/dataflows/pump-control › deploy');

    await S.load(const Locale('uk'));
    addTearDown(() => S.load(const Locale('en')));
    // the same objects, worded again; the broker's words are data
    expect(toast.title, 'Ви не можете розгорнути pump-control');
    expect(card.title, toast.title);
    expect(toast.line, 'permission_denied: needs config on dataflows');
  });

  test('a title that came with the failure is kept as it came', () {
    const given = ErrorSaid(
      id: 1,
      kind: ErrorKindTag.studio,
      icon: AppIcon.errStudio,
      thing: ErrorThingVm.unnamed(),
      titleKind: ErrorTitleTag.foreign,
      voice: ErrorVoiceTag.studio,
      foreign: ErrorForeignVm('The picker closed', 'Pick it again.'),
    );
    expect(given.title, 'The picker closed');
    expect(given.said, 'Pick it again.');
  });

  test('where the broker sent no words Studio says its own', () {
    const silent = ErrorSaid(
      id: 2,
      kind: ErrorKindTag.gone,
      icon: AppIcon.errGone,
      thing: ErrorThingVm.named('t2'),
      titleKind: ErrorTitleTag.unsupported,
      hint: ErrorHintVm.tag(HintTag.notSettable),
      status: 'not_supported',
      unsupported: true,
      call: ErrorCallVm('set', verb: ErrorVerb.write),
    );
    expect(silent.title, 't2 does not support set');
    expect(
      silent.said,
      'Its meta names no level it can be set at, so nothing was staged.',
    );
    expect(silent.line, startsWith('not_supported: Its meta names'));
  });

  test('a fault outside any action: in the background, or of a panel', () {
    ErrorSaid fault({String? screen}) => ErrorSaid(
      id: 3,
      kind: ErrorKindTag.studio,
      icon: AppIcon.errStudio,
      thing: const ErrorThingVm.unnamed(),
      titleKind: screen == null
          ? ErrorTitleTag.uncaughtBackground
          : ErrorTitleTag.uncaughtPanel,
      quiet: true,
      report: ErrorReportVm(
        type: 'StateError',
        line: 'Bad state',
        screen: screen,
        uncaught: true,
      ),
    );
    expect(fault().title, 'Studio hit a fault in the background');
    expect(fault(screen: 'Trend').title, 'Studio could not draw Trend');
    expect(fault().said, S.current.errFaultMessage);
  });

  test('a stream that is down: its toast stays, and says so', () {
    const down = ErrorSaid(
      id: 4,
      kind: ErrorKindTag.reach,
      icon: AppIcon.errReach,
      thing: ErrorThingVm.named('edge'),
      titleKind: ErrorTitleTag.stream,
      stream: 'edge',
      site: 'edge',
    );
    final toast = ToastVm.failure(down);
    expect(toast.stays, 'stays until edge is back');
    expect(toast.line, S.current.toastStream);
    expect(ToastVm.failure(denied).stays, isNull);
  });

  test('two errors are equal by what they hold; a toast by its error', () {
    expect(ToastVm.failure(denied), ToastVm.failure(denied));
    expect(ProblemVm.failure(denied), ProblemVm.failure(denied));
    const other = ErrorSaid(
      id: 8,
      kind: ErrorKindTag.rights,
      icon: AppIcon.errRights,
      thing: ErrorThingVm.named('pump-control'),
      titleKind: ErrorTitleTag.rights,
    );
    expect(ToastVm.failure(denied), isNot(ToastVm.failure(other)));
  });

  test('Copy details masks what the caller masks', () {
    final text = denied.details(
      const ErrorContext(user: 'olena', role: 'operator'),
      redact: (t) => t.replaceAll('config', '•••'),
    );
    expect(text, contains('You can’t deploy pump-control'));
    expect(text, contains('Status: permission_denied (0x21)'));
    expect(text, contains('Message: needs ••• on dataflows'));
    expect(text, contains('As: olena (operator)'));
  });
}
