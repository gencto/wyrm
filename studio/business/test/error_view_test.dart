import 'package:business/wyrm/error_view.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/error_action.dart';
import 'package:models/error_advice.dart';
import 'package:models/error_call.dart';
import 'package:models/error_chip.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_saying.dart';
import 'package:models/error_secondary.dart';
import 'package:models/error_title.dart';
import 'package:models/error_voice.dart';
import 'package:models/fault_report.dart';
import 'package:models/foreign_words.dart';
import 'package:models/gateway_field_problem.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// What is decided of one failure (errors.md §1, §2, §7): its title, who
/// spoke, the main button, the countdown. `ui` only says them.
void main() {
  StudioError refused(
    Status status, {
    String message = '',
    String key = 'wy/plant/dataflows/pump-control',
    ErrorCall call = const ErrorCall.named('deploy'),
    bool write = true,
  }) => refusalOf(
    WyrmException.of(status, message),
    key: key,
    call: call,
    write: write,
  );
  StudioError again(StudioError e) => e.copyWith(retry: Object.new);

  test('the title of each kind', () {
    expect(refused(Status.permissionDenied).titleKind, ErrorTitle.rights);
    expect(refused(Status.timeout).titleKind, ErrorTitle.reachWho);
    expect(
      refused(Status.timeout, key: 'nowhere').titleKind,
      ErrorTitle.reachNoSite,
    );
    expect(refused(Status.invalidParameter).titleKind, ErrorTitle.input);
    expect(
      refused(Status.outOfRange, call: const ErrorCall.known(.set)).titleKind,
      ErrorTitle.inputValue,
    );
    expect(refused(Status.busy).titleKind, ErrorTitle.busy);
    expect(refused(Status.notFound).titleKind, ErrorTitle.gone);
    expect(refused(Status.notSupported).titleKind, ErrorTitle.unsupported);
    expect(refused(Status.internalError).titleKind, ErrorTitle.broker);
    expect(
      const StudioError(kind: ErrorKind.reach).titleKind,
      ErrorTitle.notConnected,
    );
    expect(
      const StudioError(
        kind: ErrorKind.reach,
        call: ErrorCall.known(.logIn),
        thing: 'https://plant.local:8445',
      ).titleKind,
      ErrorTitle.reachThing,
    );
  });

  test('what Studio did on its own, and what it found itself', () {
    final sub = refused(
      Status.timeout,
      call: const ErrorCall.known(.subscribe),
    ).copyWith(quiet: true);
    expect(sub.titleKind, ErrorTitle.readFailed);
    expect(sub.copyWith(stream: 'edge').titleKind, ErrorTitle.stream);
    expect(
      sub.copyWith(call: const ErrorCall.known(.history)).titleKind,
      ErrorTitle.history,
    );
    expect(
      const StudioError(
        kind: ErrorKind.studio,
        call: ErrorCall.known(.enableDevice),
      ).titleKind,
      ErrorTitle.deviceOff,
    );
    expect(
      const StudioError(kind: ErrorKind.studio).titleKind,
      ErrorTitle.plain,
    );
    expect(
      const StudioError(
        kind: ErrorKind.input,
        call: ErrorCall.known(.read),
        hint: ErrorHint.fileNotRead(
          ManifestProblem(fault: ManifestFault.notObject),
        ),
      ).titleKind,
      ErrorTitle.studioCould,
    );
    expect(faultOf(StateError('x'), null).titleKind, ErrorTitle.studioStep);
    const report = FaultReport(type: 'StateError', uncaught: true);
    expect(
      const StudioError(kind: ErrorKind.studio, report: report).titleKind,
      ErrorTitle.uncaughtBackground,
    );
    expect(
      StudioError(
        kind: ErrorKind.studio,
        report: report.copyWith(screen: 'Trend'),
      ).titleKind,
      ErrorTitle.uncaughtPanel,
    );
    expect(
      const StudioError(
        kind: ErrorKind.studio,
        hint: ErrorHint.settingsUnreadable(),
      ).titleKind,
      ErrorTitle.startFault,
    );
  });

  test('the words of another package are kept as its own', () {
    const e = StudioError(
      kind: ErrorKind.studio,
      foreign: ForeignWords(title: 'No network', detail: 'Check the cable.'),
    );
    expect(e.titleKind, ErrorTitle.foreign);
    expect(e.silent, isFalse);
    expect(e.voice, ErrorVoice.studio);
  });

  test('who spoke: Studio, nobody, or the broker', () {
    expect(refused(Status.timeout).voice, ErrorVoice.noAnswer);
    expect(
      refused(Status.timeout, message: 'the device is slow').voice,
      ErrorVoice.broker,
    );
    expect(refused(Status.permissionDenied).voice, ErrorVoice.broker);
    expect(faultOf(StateError('x'), null).voice, ErrorVoice.studio);
    expect(
      const StudioError(
        kind: ErrorKind.input,
        hint: ErrorHint.rangeTooBig(),
      ).voice,
      ErrorVoice.studio,
    );
    expect(refused(Status.timeout).silent, isTrue);
  });

  test('the main button of each kind', () {
    expect(refused(Status.permissionDenied).action(), ErrorAction.ok);
    expect(again(refused(Status.timeout)).action(), ErrorAction.retry);
    expect(refused(Status.timeout).action(), ErrorAction.ok);
    expect(refused(Status.invalidParameter).action(), ErrorAction.form);
    expect(again(refused(Status.busy)).action(), ErrorAction.retry);
    expect(
      refused(Status.notFound).copyWith(reload: Object.new).action(),
      ErrorAction.refresh,
    );
    expect(refused(Status.notFound).action(), ErrorAction.ok);
    expect(refused(Status.internalError).action(), ErrorAction.log);
    expect(faultOf(StateError('x'), null).action(), ErrorAction.ok);
    // from Problems a write is not repeated; a read is
    expect(
      again(refused(Status.timeout)).action(readOnly: true),
      ErrorAction.ok,
    );
    expect(
      again(refused(Status.timeout, write: false)).action(readOnly: true),
      ErrorAction.retry,
    );
  });

  test('what its words are: the broker, another package, a hint, a fault; '
      'else a site that did not answer, a status alone, or nothing', () {
    expect(
      refused(Status.timeout, message: 'slow').saying,
      ErrorSaying.broker,
    );
    expect(
      const StudioError(
        kind: ErrorKind.studio,
        foreign: ForeignWords(
          title: 'The picker closed',
          detail: 'Pick it again.',
        ),
      ).saying,
      ErrorSaying.foreign,
    );
    expect(
      const StudioError(
        kind: ErrorKind.input,
        hint: ErrorHint.rangeTooBig(),
      ).saying,
      ErrorSaying.hint,
    );
    expect(faultOf(StateError('x'), null).saying, ErrorSaying.fault);
    expect(refused(Status.timeout).saying, ErrorSaying.silentReach);
    expect(
      refused(Status.timeout, key: 'nowhere').saying,
      ErrorSaying.silentStatus,
    );
    expect(const StudioError(kind: ErrorKind.gone).saying, ErrorSaying.nothing);
  });

  test('what you can do, for each kind', () {
    expect(refused(Status.permissionDenied).advice(), [ErrorAdvice.rights]);
    expect(refused(Status.permissionDenied).advice(role: 'operator'), [
      ErrorAdvice.rights,
      ErrorAdvice.rightsRole,
    ]);
    expect(refused(Status.permissionDenied).advice(role: ''), [
      ErrorAdvice.rights,
    ]);
    expect(refused(Status.timeout).advice(), [ErrorAdvice.reach]);
    expect(const StudioError(kind: ErrorKind.reach).advice(), [
      ErrorAdvice.reachLogin,
    ]);
    expect(refused(Status.invalidParameter).advice(), [ErrorAdvice.input]);
    expect(
      refused(Status.invalidParameter).copyWith(field: 'unit').advice(),
      [ErrorAdvice.inputField],
    );
    expect(again(refused(Status.busy)).advice(), [ErrorAdvice.busyAuto]);
    expect(again(refused(Status.busy)).advice(readOnly: true), [
      ErrorAdvice.busy,
    ]);
    expect(refused(Status.notFound).advice(), [ErrorAdvice.gone]);
    expect(refused(Status.notSupported).advice(), [ErrorAdvice.unsupported]);
    final at = DateTime(2026, 11, 19, 11, 52);
    expect(refused(Status.internalError).copyWith(at: at).advice(), [
      ErrorAdvice.brokerLog,
    ]);
    expect(const StudioError(kind: ErrorKind.broker).advice(), [
      ErrorAdvice.brokerSaid,
    ]);
    expect(faultOf(StateError('x'), null).advice(), [
      ErrorAdvice.studio,
      ErrorAdvice.report,
    ]);
    expect(const StudioError(kind: ErrorKind.studio).advice(), [
      ErrorAdvice.studio,
    ]);
  });

  test('the second button, the write note and the chip', () {
    expect(
      refused(Status.permissionDenied).secondary(),
      ErrorSecondary.seeAccess,
    );
    expect(refused(Status.timeout).secondary(), ErrorSecondary.none);
    expect(refused(Status.invalidParameter).secondary(), ErrorSecondary.none);
    expect(again(refused(Status.timeout)).secondary(), ErrorSecondary.close);
    expect(
      again(refused(Status.timeout)).secondary(readOnly: true),
      ErrorSecondary.none,
    );
    expect(refused(Status.internalError).secondary(), ErrorSecondary.close);
    expect(refused(Status.timeout).writeNote, isTrue);
    expect(refused(Status.timeout, write: false).writeNote, isFalse);
    expect(refused(Status.permissionDenied).writeNote, isFalse);
    expect(refused(Status.timeout).chip, ErrorChip.status);
    expect(const StudioError(kind: ErrorKind.reach).chip, ErrorChip.kind);
    expect(faultOf(StateError('x'), null).chip, ErrorChip.studio);
  });

  test('busy counts down, with the hint of the broker when it gave one', () {
    final busy = again(refused(Status.busy));
    expect(busy.countdown(), busyWait);
    expect(busy.copyWith(wait: 9).countdown(), 9);
    expect(busy.countdown(readOnly: true), isNull);
    expect(refused(Status.busy).countdown(), isNull, reason: 'no retry');
    expect(again(refused(Status.timeout)).countdown(), isNull);
  });

  test('Details open for the broker and for Studio; Try again in a toast '
      'repeats no write', () {
    expect(refused(Status.internalError).detailsOpen, isTrue);
    expect(faultOf(StateError('x'), null).detailsOpen, isTrue);
    expect(refused(Status.permissionDenied).detailsOpen, isFalse);
    expect(again(refused(Status.timeout)).offersRetry, isFalse);
    expect(again(refused(Status.timeout, write: false)).offersRetry, isTrue);
  });

  test('the gateway field refuses user:password@; nothing else of it is '
      'lost', () {
    // the user and the password have their own fields
    for (final typed in [
      'https://olena:gw-pass@plant.local:8445',
      'olena@plant.local:8445',
      'http://a:8445, https://olena:pw@b:8445',
    ]) {
      expect(gatewayProblemOf(typed), GatewayFieldProblem.credentials);
      expect(
        [for (final g in parseGateways(typed)) g.text],
        isNot(contains(contains('olena'))),
      );
    }
    expect(parseGateways('https://olena:gw-pass@plant.local:8445'), isEmpty);
    expect(
      [for (final g in parseGateways('http://a:8445, b:8446')) g.text],
      ['http://a:8445', 'http://b:8446'],
    );
    expect(gatewayProblemOf('http://a:8445, b:8446'), isNull);
    expect(gatewayProblemOf('  '), GatewayFieldProblem.empty);
    expect(gatewayProblemOf('ftp://a'), GatewayFieldProblem.invalid);
    // what is kept on disk keeps every part, without the credentials
    expect(
      gatewayFieldWithoutCredentials(
        'https://olena:gw-pass@plant.local:8445, u@edge:8446,http://c',
      ),
      'https://plant.local:8445, edge:8446,http://c',
    );
  });
}
