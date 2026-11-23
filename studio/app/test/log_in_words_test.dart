import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/show_step_up_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:business/wyrm/session.dart';
import 'package:device_key/testing.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/answer_fault.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/lock_error.dart';
import 'package:models/login_failure.dart';
import 'package:models/node_info.dart';
import 'package:models/refusal_code.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_relation.dart';
import 'package:models/staged_change.dart';
import 'package:models/step_up_deed.dart';
import 'package:models/step_up_error.dart';
import 'package:models/step_up_line.dart';
import 'package:models/step_up_request.dart';
import 'package:models/trust_refusal.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:ui/inputs/range_probe.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'log_in_words.dart';
import 'support/log_in_app.dart';
import 'support/words.dart';

/// The log-in page, the idle lock and the step-up as the store makes them
/// (studio-rules, step 1): every word of each main state, in English and
/// in Ukrainian for the main ones. Written before the three connectors
/// moved their words into `ui`, so it holds the words they gave then.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  setUpAll(loadFonts);
  const uk = Locale('uk');

  /// The page with the field filled and a recent gateway beside it.
  AppState form(AppState a) => a.copyWith.login(
    gateway: gw,
    user: user,
    recent: const IListConst([gw, 'http://127.0.0.1:8445']),
  );

  Future<void> logIn(
    WidgetTester t,
    String name, {
    LogInApp? app,
    AppState Function(AppState)? before,
    AppState Function(AppState)? after,
    Type? inFlight,
    Future<void> Function(WidgetTester, LogInApp)? setup,
    Locale locale = const Locale('en'),
  }) async {
    final a = app ?? LogInApp();
    await setup?.call(t, a);
    a.put(before ?? form);
    await a.pumpLogIn(t, locale: locale);
    if (inFlight != null) {
      a.store.hold(inFlight);
    }
    if (after != null) {
      a.put(after);
    }
    if (inFlight != null || after != null) {
      await a.settle(t);
    }
    expectWords(name, a.logInWords(t), logInWords);
    await a.leave(t);
  }

  group('the password form', () {
    testWidgets('answered', (t) => logIn(t, 'form'), variant: mac);
    testWidgets(
      'answered, uk',
      (t) => logIn(t, 'form uk', locale: uk),
      variant: mac,
    );
    testWidgets(
      'the field empty',
      (t) => logIn(t, 'empty', before: (a) => a.copyWith.login(gateway: '')),
      variant: mac,
    );
    testWidgets(
      'the field never written: the demo gateway as its hint',
      (t) => logIn(t, 'default', before: (a) => a),
      variant: mac,
    );
    testWidgets(
      'no answer',
      (t) => logIn(
        t,
        'no answer',
        app: LogInApp(
          answer: const GatewayProbe.noAnswer(AnswerFault.timedOut()),
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'signing in, the second step',
      (t) => logIn(
        t,
        'signing',
        inFlight: LogInAction,
        after: (a) => a.copyWith.login(step: 1),
      ),
      variant: mac,
    );
    testWidgets(
      'the password refused',
      (t) => logIn(
        t,
        'wrong',
        after: (a) => a.copyWith.login(failure: LoginFailure.wrong),
      ),
      variant: mac,
    );
    for (final (name, locale) in [
      ('unreachable', const Locale('en')),
      ('unreachable uk', uk),
    ]) {
      testWidgets(
        'no gateway answered, a standby set: $name',
        (t) => logIn(
          t,
          name,
          locale: locale,
          app: LogInApp(
            answer: const GatewayProbe.noAnswer(AnswerFault.timedOut()),
          ),
          before: (a) => a.copyWith.login(
            gateway: '$gw, $standbyGw',
            user: user,
          ),
          after: (a) => a.copyWith.login(
            failure: LoginFailure.unreachable,
            reason: const AnswerFault.refusedAfter(3),
          ),
        ),
        variant: mac,
      );
    }
  });

  group('after the password', () {
    AppState welcome(AppState a) => a.copyWith(
      session: a.session.copyWith(token: 'user:olena'),
      site: a.site.copyWith(
        name: 'plant',
        user: 'user:olena',
        role: 'engineer',
        choices: const IListConst([
          SiteChoice(site: 'plant'),
          SiteChoice(site: 'edge', relation: SiteRelation.downstream),
          SiteChoice(site: 'central', relation: SiteRelation.upstream),
        ]),
      ),
      nodes: a.nodes.copyWith(
        table: {
          for (final k in [
            'wy/plant/downstream/modbus',
            'wy/plant/downstream/bacnet',
            'wy/plant/downstream/modbus/pump',
          ])
            k: NodeInfo(key: k, name: k.split('/').last),
        }.lock,
      ),
      login: a.login.copyWith(preload: 2, preloadLate: const IListConst([1])),
    );

    testWidgets(
      'the welcome while the tree opens',
      (t) => logIn(t, 'welcome', after: welcome),
      variant: mac,
    );
    testWidgets(
      'the welcome, uk',
      (t) => logIn(t, 'welcome uk', after: welcome, locale: uk),
      variant: mac,
    );

    AppState offer(AppState a) => welcome(a).copyWith.device(
      stage: UnlockStage.offer,
      policy: const DevicePolicy(enabled: true),
    );

    testWidgets(
      'the offer, Touch ID here',
      (t) => logIn(t, 'offer', after: offer),
      variant: mac,
    );
    testWidgets(
      'the offer, uk',
      (t) => logIn(t, 'offer uk', after: offer, locale: uk),
      variant: mac,
    );
    testWidgets(
      'the offer with a standby',
      (t) => logIn(
        t,
        'offer standby',
        before: (a) => form(a).copyWith.login(gateway: '$gw, $standbyGw'),
        after: offer,
      ),
      variant: mac,
    );
    testWidgets(
      'the offer, no biometric here',
      (t) => logIn(
        t,
        'offer none',
        app: LogInApp(
          keys: FakeDeviceKey(availability: DeviceKeyAvailability.none),
        ),
        after: (a) => offer(a).copyWith.device(available: false),
      ),
      variant: mac,
    );
  });

  group('the unlock forms', () {
    /// Enrolled two hours ago, the key last used then.
    Future<void> enrolled(WidgetTester t, LogInApp a) async {
      await a.enroll(t);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      a.put(
        (s) => s.copyWith.device(
          added: DateTime(2026, 11, 3, 10).millisecondsSinceEpoch ~/ 1000,
          lastUsed: now - 2 * 3600,
        ),
      );
    }

    /// The unlock form [name] of an enrolled computer. The page's own
    /// prompt on open answers [answer]: with [shown] false its form stays
    /// (a cancel, a lockout); else the form is laid in as [after] says.
    Future<void> unlockForm(
      WidgetTester t,
      String name, {
      AppState Function(AppState)? after,
      Locale locale = const Locale('en'),
      FakeAnswer answer = FakeAnswer.cancelled,
      bool shown = true,
    }) async {
      final app = LogInApp();
      await logIn(
        t,
        name,
        app: app,
        setup: (t, a) async {
          await enrolled(t, a);
          a.keys.answer = answer;
        },
        locale: locale,
        after: (a) {
          final s = a.copyWith.device(
            added: DateTime(2026, 11, 3, 10).millisecondsSinceEpoch ~/ 1000,
            lastUsed: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7200,
          );
          if (!shown) {
            return s;
          }
          final u = s.copyWith.device(
            stage: UnlockStage.unlock,
            fallback: null,
          );
          return after == null ? u : after(u);
        },
      );
    }

    testWidgets('Welcome back', (t) => unlockForm(t, 'unlock'), variant: mac);
    testWidgets(
      'Welcome back, uk',
      (t) => unlockForm(t, 'unlock uk', locale: uk),
      variant: mac,
    );
    testWidgets(
      'the key being checked',
      (t) => unlockForm(
        t,
        'checking',
        after: (a) => a.copyWith.device(stage: UnlockStage.checking),
      ),
      variant: mac,
    );
    testWidgets(
      'the prompt cancelled',
      (t) => unlockForm(t, 'fallback cancelled', shown: false),
      variant: mac,
    );
    testWidgets(
      'locked out',
      (t) => unlockForm(
        t,
        'fallback locked out',
        answer: FakeAnswer.lockout,
        shown: false,
      ),
      variant: mac,
    );
    testWidgets(
      'Use the password: the fallback without a notice',
      (t) => unlockForm(
        t,
        'fallback plain',
        after: (a) => a.copyWith.device(stage: UnlockStage.fallback),
      ),
      variant: mac,
    );
    testWidgets(
      'fingerprints changed',
      (t) => unlockForm(
        t,
        'changed',
        after: (a) => a.copyWith.device(
          stage: UnlockStage.changed,
          keyId: null,
          stale: true,
        ),
      ),
      variant: mac,
    );
    for (final r in UnlockRefusal.values) {
      testWidgets(
        'signed out: ${r.name}',
        (t) => unlockForm(
          t,
          'signed out ${r.name}',
          after: (a) => a.copyWith.device(
            stage: UnlockStage.signedOut,
            refusal: r,
            keyId: r == UnlockRefusal.passwordDue ? a.device.keyId : null,
          ),
        ),
        variant: mac,
      );
    }
    testWidgets(
      'signed out, uk',
      (t) => unlockForm(
        t,
        'signed out uk',
        locale: uk,
        after: (a) => a.copyWith.device(
          stage: UnlockStage.signedOut,
          refusal: UnlockRefusal.removed,
          keyId: null,
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'no biometric here',
      (t) => logIn(
        t,
        'no biometrics',
        app: LogInApp(
          keys: FakeDeviceKey(availability: DeviceKeyAvailability.none),
        ),
      ),
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  group('find on this network', () {
    final labCode = caCode(testCaDer);

    GatewayInfo info(
      String site, {
      String? pair,
      List<String> up = const [],
      String minStudio = '1.0.0',
      bool tls = true,
      bool ca = false,
      List<String> names = const [],
    }) => GatewayInfo(
      site: site,
      version: '0.1.0',
      tls: tls,
      pair: pair,
      up: up,
      minStudio: minStudio,
      ca: ca ? testCaDer : null,
      caFp: ca ? labCode : null,
      names: names,
    );

    Announcement announce(
      String site,
      String address, {
      Map<String, String> txt = const {},
    }) => Announcement(
      name: site,
      addresses: [address],
      port: 8446,
      txt: {'site': site, 'tls': '1', 'v': '0.1.0', ...txt},
    );

    /// Six gateways: one used before with a standby, one new, one below
    /// plant, one too new for this Studio, one on plain HTTP, one that does
    /// not answer `/api/info`.
    LogInApp network() {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.10:8446'],
          info('plant', pair: '10.0.7.11:8446', names: ['10.0.7.10']),
        )
        ..trusted.add('https://10.0.7.10:8446')
        ..serve(
          ['https://10.0.7.20:8446'],
          info('lab', ca: true, names: ['10.0.7.20']),
        )
        ..serve(
          ['https://10.0.7.31:8446'],
          info('line3', up: ['plant', 'edge'], names: ['10.0.7.31']),
        )
        ..trusted.add('https://10.0.7.31:8446')
        ..serve(
          ['https://10.0.7.40:8446'],
          info('old', minStudio: '9.0.0', names: ['10.0.7.40']),
        )
        ..trusted.add('https://10.0.7.40:8446')
        ..serve(['http://10.0.7.50:8446'], info('bare', tls: false))
        ..fail('https://10.0.7.60:8446', InfoFault.missing);
      return LogInApp(
        net: net,
        found: [
          announce('plant', '10.0.7.10', txt: {'pair': '10.0.7.11:8446'}),
          announce('lab', '10.0.7.20', txt: {'fp': labCode}),
          announce('line3', '10.0.7.31', txt: {'up': 'plant,edge'}),
          announce('old', '10.0.7.40'),
          announce('bare', '10.0.7.50', txt: {'tls': '0'}),
          announce('gone', '10.0.7.60'),
        ],
      );
    }

    Future<void> openFind(
      WidgetTester t,
      String name, {
      required LogInApp app,
      Locale locale = const Locale('en'),
      Future<void> Function(WidgetTester)? then,
    }) async {
      app.put(
        (a) => form(a).copyWith.login(
          recent: const IListConst(['https://10.0.7.10:8446']),
        ),
      );
      await app.pumpLogIn(t, locale: locale);
      await t.tap(find.text(_findLabel(locale)));
      await app.settle(t);
      await then?.call(t);
      await app.settle(t);
      expectWords(name, app.logInWords(t), logInWords);
      await app.leave(t);
    }

    testWidgets(
      'the rows found',
      (t) => openFind(t, 'found', app: network()),
      variant: mac,
    );
    testWidgets(
      'the rows found, uk',
      (t) => openFind(t, 'found uk', app: network(), locale: uk),
      variant: mac,
    );
    testWidgets('looking', (t) async {
      final app = LogInApp()..put(form);
      await app.pumpLogIn(t);
      app.put(
        (a) => a.copyWith.discovery(
          open: true,
          scanning: true,
          network: 'en0',
          subnet: '10.0.7.0/24',
        ),
      );
      await app.settle(t);
      expectWords('looking', app.logInWords(t), logInWords);
      app.put(
        (a) => a.copyWith.discovery(
          probing: true,
          range: '10.0.7.0/26',
          rangePort: '8446',
        ),
      );
      await app.settle(t);
      expectWords('probing', app.logInWords(t), logInWords);
      await app.leave(t);
    }, variant: mac);
    testWidgets(
      'nothing found, a bad range and port typed',
      (t) => openFind(
        t,
        'nothing',
        app: LogInApp(),
        then: (t) async {
          final fields = find.descendant(
            of: find.byType(RangeProbe),
            matching: find.byType(EditableText),
          );
          await t.enterText(fields.first, '10.0.0.0/16');
          await t.enterText(fields.last, '70000');
        },
      ),
      variant: mac,
    );
    testWidgets(
      'nothing found, a malformed range',
      (t) => openFind(
        t,
        'nothing malformed',
        app: LogInApp(),
        then: (t) async {
          final fields = find.descendant(
            of: find.byType(RangeProbe),
            matching: find.byType(EditableText),
          );
          await t.enterText(fields.first, '10.0.7');
        },
      ),
      variant: mac,
    );
    testWidgets(
      'nothing found, uk',
      (t) => openFind(t, 'nothing uk', app: LogInApp(), locale: uk),
      variant: mac,
    );
    for (final (name, locale) in [
      ('trust', const Locale('en')),
      ('trust uk', uk),
    ]) {
      testWidgets(
        'the trust card of a new CA: $name',
        (t) => openFind(
          t,
          name,
          app: network(),
          locale: locale,
          then: (t) async {
            await t.tap(find.text('lab'));
          },
        ),
        variant: mac,
      );
    }
    for (final (why, refusal) in [
      ('no_answer', TrustRefusal.noAnswer),
      ('changed', TrustRefusal.changed),
      ('mismatch', TrustRefusal.mismatch),
      ('chain', TrustRefusal.chain),
    ]) {
      testWidgets('the trust refused: $why', (t) async {
        final app = network();
        await openFind(
          t,
          'trust refused $why',
          app: app,
          then: (t) async {
            await t.tap(find.text('lab'));
            await app.settle(t);
            app.put((a) => a.copyWith.discovery(trustRefused: refusal));
          },
        );
      }, variant: mac);
    }
  });

  group('the idle lock', () {
    Future<void> lock(
      WidgetTester t,
      String name, {
      required LogInApp app,
      AppState Function(AppState)? put,
      Locale locale = const Locale('en'),
    }) async {
      await app.logIn(t);
      app.put(
        (a) => a.copyWith.device(locked: true, lockAfter: 15),
      );
      if (put != null) {
        app.put(put);
      }
      await app.pumpLock(t, locale: locale);
      expectWords(name, app.lockWords(t), logInWords);
      await app.leave(t);
    }

    Future<LogInApp> keyed(WidgetTester t) async {
      final a = LogInApp();
      await a.enroll(t);
      return a;
    }

    testWidgets(
      'with the key, three changes kept',
      (t) async => lock(
        t,
        'lock',
        app: await keyed(t),
        put: (a) => a.copyWith(
          changes: a.changes.copyWith(
            view: const IListConst(['c0', 'c1', 'c2']),
            table: {
              for (var i = 0; i < 3; i++)
                'c$i': StagedChange(
                  id: 'c$i',
                  op: ChangeOp.edit,
                  key: 'wy/plant/sys/x$i',
                  field: 'value',
                  to: ChangeSide.text('$i'),
                  level: Perm.write,
                  value: i,
                ),
            }.lock,
          ),
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'with the key, uk',
      (t) async => lock(t, 'lock uk', app: await keyed(t), locale: uk),
      variant: mac,
    );
    testWidgets(
      'a wrong password',
      (t) => lock(
        t,
        'lock wrong',
        app: LogInApp(),
        put: (a) => a.copyWith.device(
          lockError: const LockError.wrongPassword(),
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'a refusal the gateway named, in Studio words',
      (t) => lock(
        t,
        'lock refused',
        app: LogInApp(),
        put: (a) => a.copyWith.device(
          lockError: const LockError.gateway(RefusalCode.tooManyDevices),
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'a refusal with no code, in its own words',
      (t) => lock(
        t,
        'lock other',
        app: LogInApp(),
        put: (a) => a.copyWith.device(
          lockError: const LockError.refused('too many tries'),
        ),
      ),
      variant: mac,
    );
    testWidgets(
      'no key here: the password at once',
      (t) => lock(t, 'lock password', app: LogInApp()),
      variant: mac,
    );
  });

  group('the step-up', () {
    const lines = [
      StepUpLine(
        level: Perm.config,
        deed: StepUpDeed.set('value'),
        key: 'wy/plant/sys/x',
      ),
      StepUpLine(level: Perm.write, deed: StepUpDeed.addUser('ivan')),
    ];

    Future<void> stepUp(
      WidgetTester t,
      String name, {
      StepUpRequest Function(StepUpRequest)? change,
      Locale locale = const Locale('en'),
    }) async {
      final app = LogInApp();
      await app.enroll(t);
      await app.logIn(t);
      app.store.dispatchSync(ShowStepUpAction(lines));
      if (change != null) {
        app.put((a) => a.copyWith.device(stepUp: change(a.device.stepUp!)));
      }
      await app.pumpStepUp(t, locale: locale);
      expectWords(name, app.stepUpWords(t), logInWords);
      await app.leave(t);
    }

    testWidgets('with the key', (t) => stepUp(t, 'step-up'), variant: mac);
    testWidgets(
      'with the key, uk',
      (t) => stepUp(t, 'step-up uk', locale: uk),
      variant: mac,
    );
    testWidgets(
      'waiting for Touch ID',
      (t) => stepUp(t, 'step-up busy', change: (r) => r.copyWith(busy: true)),
      variant: mac,
    );
    for (final (name, error) in [
      ('step-up wrong', const StepUpError.wrongPassword()),
      ('step-up cancelled', stepUpErrorOf(const SignCancelled())),
      ('step-up locked', stepUpErrorOf(const SignLockout())),
      ('step-up refused', const StepUpError.gateway(RefusalCode.deviceRemoved)),
      ('step-up said', const StepUpError.refused('too many tries')),
    ]) {
      testWidgets(
        'an error: $name',
        (t) => stepUp(t, name, change: (r) => r.copyWith(error: error)),
        variant: mac,
      );
    }
    testWidgets(
      'the password only',
      (t) => stepUp(
        t,
        'step-up password',
        change: (r) => r.copyWith(passwordOnly: true),
      ),
      variant: mac,
    );
  });
}

/// The tooltip of *Find on this network* in [locale].
String _findLabel(Locale locale) => locale.languageCode == 'uk'
    ? 'Знайти в цій мережі'
    : 'Find on this network';
