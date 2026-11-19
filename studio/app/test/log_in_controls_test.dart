import 'dart:convert';

import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/lock_action.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:business/wyrm/session.dart';
import 'package:device_key/testing.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/answer_fault.dart';
import 'package:models/login_failure.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:ui/buttons/unlock_button.dart';
import 'package:ui/inputs/boxed_form_field.dart';
import 'package:ui/inputs/range_probe.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/log_in_app.dart';

/// What each control of the log-in page, the lock and the step-up does,
/// read from the store, the fake gateway, the key store and the network
/// (studio-rules, step 1): never from which actions ran, so it holds
/// before and after the rewrite. The steps that leave the page for
/// Studio are in `log_in_flow_test.dart`, with the router.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  setUpAll(loadFonts);

  setUp(() => S.load(const Locale('en')));

  AppState form(AppState a) => a.copyWith.login(
    gateway: gw,
    user: user,
    recent: const IListConst([gw, 'http://127.0.0.1:8445']),
  );

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is BoxedFormField && w.label == label,
  );

  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(EditableText));

  group('the password form', () {
    testWidgets('typing the gateway writes it; leaving the field probes it', (
      t,
    ) async {
      final app = LogInApp()..put(form);
      await app.pumpLogIn(t);
      app.login.probed.clear();

      await t.enterText(input('Gateway'), 'https://lab.local:8446');
      await app.settle(t);
      expect(app.store.state.login.gateway, 'https://lab.local:8446');
      expect(app.login.probed, isEmpty, reason: 'not while typing');

      await t.tap(input('User'));
      await app.settle(t);
      expect(app.login.probed, [Uri.parse('https://lab.local:8446')]);
      await t.enterText(input('User'), 'ivan');
      await t.enterText(input('Password'), 'secret');
      expect(app.store.state.login.user, 'ivan');
      expect(app.store.state.login.password, 'secret');
      await app.leave(t);
    }, variant: mac);

    testWidgets('a recent chip fills the field, probes it, reads its key', (
      t,
    ) async {
      final app = LogInApp();
      await app.enroll(t);
      app.put((a) => form(a).copyWith.login(gateway: 'http://127.0.0.1:8445'));
      app.keys.answer = FakeAnswer.cancelled;
      await app.pumpLogIn(t);
      expect(app.store.state.device.stage, UnlockStage.none);
      app.login.probed.clear();

      await t.tap(find.text('plant:8446'));
      await app.settle(t);

      expect(app.store.state.login.gateway, gw);
      expect(app.login.probed, contains(Uri.parse(gw)));
      expect(
        app.store.state.device.keyId,
        isNotNull,
        reason: 'the key of plant read for the form',
      );
      await app.leave(t);
    }, variant: mac);

    testWidgets('a refused password: asked once, said inline, field kept', (
      t,
    ) async {
      final app = LogInApp(
        login: FakeLogin(
          error: WyrmException.of(Status.permissionDenied, 'bad credentials'),
        ),
      )..put((a) => form(a).copyWith.login(password: 'nope'));
      await app.pumpLogIn(t);

      await t.tap(find.widgetWithText(InkWell, 'Log in').last);
      await app.settle(t);

      expect(app.login.password, 'nope');
      expect(app.login.gateways, [Uri.parse(gw)]);
      expect(app.store.state.login.failure, LoginFailure.wrong);
      expect(app.store.state.session.token, isNull);
      expect(find.text(S.current.wrongPassword), findsOneWidget);
      await app.leave(t);
    }, variant: mac);

    testWidgets('the field never written: Log in sends the demo gateway', (
      t,
    ) async {
      final app = LogInApp(
        login: FakeLogin(
          error: WyrmException.of(Status.permissionDenied, 'bad credentials'),
        ),
      )..put((a) => a.copyWith.login(user: user, password: 'nope'));
      await app.pumpLogIn(t);

      await t.tap(find.widgetWithText(InkWell, 'Log in').last);
      await app.settle(t);

      expect(app.store.state.login.gateway, 'http://127.0.0.1:8445');
      expect(app.login.gateways, [Uri.parse('http://127.0.0.1:8445')]);
      await app.leave(t);
    }, variant: mac);

    testWidgets('no answer: the alert; Use the standby tries it first', (
      t,
    ) async {
      final app =
          LogInApp(answer: const GatewayProbe.noAnswer(AnswerFault.timedOut()))
            ..put(
              (a) => a.copyWith.login(
                gateway: '$gw, $standbyGw',
                user: user,
                password: password,
              ),
            );
      await app.pumpLogIn(t);
      app.login.probed.clear();

      await t.tap(find.widgetWithText(InkWell, 'Log in').last);
      await app.settle(t);
      expect(app.store.state.login.failure, LoginFailure.unreachable);
      expect(app.login.probed, [Uri.parse(gw), Uri.parse(standbyGw)]);
      expect(app.login.gateways, isNull, reason: 'no login tried');
      app.login.probed.clear();

      await t.tap(find.text('Use the standby'));
      await app.settle(t);
      expect(app.store.state.login.gateway, '$standbyGw, $gw');
      expect(app.login.probed, [Uri.parse(standbyGw), Uri.parse(gw)]);
      await app.leave(t);
    }, variant: mac);
  });

  group('find on this network', () {
    final code = caCode(testCaDer);

    LogInApp network() {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.10:8446'],
          const GatewayInfo(
            site: 'plant',
            version: '0.1.0',
            tls: true,
            names: ['10.0.7.10'],
          ),
        )
        ..trusted.add('https://10.0.7.10:8446')
        ..serve(
          ['https://10.0.7.20:8446'],
          GatewayInfo(
            site: 'lab',
            version: '0.1.0',
            tls: true,
            ca: testCaDer,
            caFp: code,
            names: const ['10.0.7.20'],
          ),
        );
      return LogInApp(
        net: net,
        found: [
          for (final (site, ip) in [
            ('plant', '10.0.7.10'),
            ('lab', '10.0.7.20'),
          ])
            Announcement(
              name: site,
              addresses: [ip],
              port: 8446,
              txt: {'site': site, 'tls': '1', 'v': '0.1.0'},
            ),
        ],
      );
    }

    testWidgets('Find opens the panel and browses; again closes it', (
      t,
    ) async {
      final app = network()..put(form);
      await app.pumpLogIn(t);

      await t.tap(find.text('Find on this network'));
      await app.settle(t);
      expect(app.store.state.discovery.open, isTrue);
      expect(app.store.state.discovery.found.keys.toSet(), {'plant', 'lab'});
      final scan = app.store.state.discovery.scan;

      await t.tap(find.text('Look again'));
      await app.settle(t);
      expect(app.store.state.discovery.scan, greaterThan(scan));

      await t.tap(find.text('Find on this network'));
      await app.settle(t);
      expect(app.store.state.discovery.open, isFalse);
      expect(find.text('lab'), findsNothing);
      await app.leave(t);
    }, variant: mac);

    testWidgets('a known row fills the field and probes it', (t) async {
      final app = network()..put(form);
      await app.pumpLogIn(t);
      await t.tap(find.text('Find on this network'));
      await app.settle(t);
      app.login.probed.clear();

      await t.tap(find.text('plant'));
      await app.settle(t);

      expect(app.store.state.login.gateway, 'https://10.0.7.10:8446');
      expect(app.login.probed, [Uri.parse('https://10.0.7.10:8446')]);
      expect(app.store.state.discovery.trustPending, isNull);
      await app.leave(t);
    }, variant: mac);

    testWidgets(
      'a new CA: the card shows the code of the CA it sent; Trust pins it',
      (t) async {
        final app = network()..put(form);
        await app.pumpLogIn(t);
        await t.tap(find.text('Find on this network'));
        await app.settle(t);
        app.login.probed.clear();

        await t.tap(find.text('lab'));
        await app.settle(t);
        expect(app.store.state.discovery.trustPending, 'lab');
        // Not reached before its CA is trusted.
        expect(app.login.probed, isEmpty, reason: 'nothing before the trust');
        // The code is computed here from the CA's bytes, not taken from
        // what the gateway claims.
        for (final g in codeGroups(code)) {
          expect(find.text(g), findsOneWidget, reason: g);
        }

        await t.tap(find.text('It matches · trust lab'));
        await app.settle(t);

        final pin = app.store.state.discovery.pins['https://10.0.7.20:8446'];
        expect(pin?.code, code);
        expect(pin?.ca, base64Encode(testCaDer));
        expect(app.store.state.discovery.trustPending, isNull);
        // Probed under the new pin once it is trusted.
        expect(app.login.probed, [Uri.parse('https://10.0.7.20:8446')]);
        await app.leave(t);
      },
      variant: mac,
    );

    testWidgets('Cancel on the card pins nothing and goes back', (t) async {
      final app = network()..put(form);
      await app.pumpLogIn(t);
      await t.tap(find.text('Find on this network'));
      await app.settle(t);
      await t.tap(find.text('lab'));
      await app.settle(t);

      await t.tap(find.text('Cancel'));
      await app.settle(t);

      expect(app.store.state.discovery.trustPending, isNull);
      expect(app.store.state.discovery.pins, isEmpty);
      expect(find.text('lab'), findsOneWidget, reason: 'the panel again');
      await app.leave(t);
    }, variant: mac);

    testWidgets('Probe sends one read per address; a bad range sends none', (
      t,
    ) async {
      final app = LogInApp()..put(form);
      await app.pumpLogIn(t);
      await t.tap(find.text('Find on this network'));
      await app.settle(t);

      final fields = find.descendant(
        of: find.byType(RangeProbe),
        matching: find.byType(EditableText),
      );
      final range = fields.first;
      await t.enterText(range, '10.0.0.0/16');
      await app.settle(t);
      await t.tap(find.text('Probe'));
      await app.settle(t);
      expect(app.net.unverified, isEmpty, reason: 'too big: nothing sent');

      await t.enterText(range, '10.0.7.0/30');
      await t.enterText(fields.last, '9000');
      await app.settle(t);
      await t.tap(find.text('Probe'));
      await app.settle(t);
      expect(app.net.unverified.map((u) => '$u').toSet(), {
        'https://10.0.7.1:9000',
        'https://10.0.7.2:9000',
      });
      await app.leave(t);
    }, variant: mac);

    testWidgets('Open settings opens the local network privacy pane', (
      t,
    ) async {
      final launcher = _Launcher();
      final was = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = was);
      final app = LogInApp()..put(form);
      await app.pumpLogIn(t);
      await t.tap(find.text('Find on this network'));
      await app.settle(t);

      await t.tap(find.text('Open settings'));
      await app.settle(t);

      const pane =
          'x-apple.systempreferences:com.apple.preference.security'
          '?Privacy_LocalNetwork';
      expect(launcher.launched, [pane]);
      await app.leave(t);
    }, variant: mac);
  });

  group('the unlock form', () {
    Future<LogInApp> enrolled(WidgetTester t, FakeAnswer answer) async {
      final app = LogInApp();
      await app.enroll(t);
      app
        ..keys.answer = answer
        ..put(form);
      return app;
    }

    testWidgets('the page prompts once on open, with its words', (t) async {
      final app = await enrolled(t, FakeAnswer.cancelled);
      await app.pumpLogIn(t);

      expect(app.keys.reasons, ['sign in to plant as olena']);
      expect(app.store.state.device.stage, UnlockStage.fallback);
      expect(app.store.state.device.keyId, isNotNull, reason: 'key kept');
      await app.leave(t);
    }, variant: mac);

    testWidgets('the round button prompts again', (t) async {
      final app = await enrolled(t, FakeAnswer.cancelled);
      await app.pumpLogIn(t);
      app
        ..put((a) => a.copyWith.device(stage: UnlockStage.unlock))
        ..keys.reasons.clear();
      await app.settle(t);

      await t.tap(find.bySemanticsLabel('Unlock with Touch ID').first);
      await app.settle(t);

      expect(app.keys.reasons, ['sign in to plant as olena']);
      await app.leave(t);
    }, variant: mac);

    testWidgets('Use the password: the password for the same user', (
      t,
    ) async {
      final app = await enrolled(t, FakeAnswer.cancelled);
      await app.pumpLogIn(t);
      app.put((a) => a.copyWith.device(stage: UnlockStage.unlock));
      await app.settle(t);

      await t.tap(find.text('Use the password'));
      await app.settle(t);

      expect(app.store.state.device.stage, UnlockStage.fallback);
      expect(app.store.state.device.keyId, isNotNull);
      expect(find.text('Password for olena'), findsOneWidget);
      await app.leave(t);
    }, variant: mac);

    testWidgets('Another account or gateway: the form, the key kept', (
      t,
    ) async {
      final app = await enrolled(t, FakeAnswer.cancelled);
      await app.pumpLogIn(t);

      await t.tap(find.text('Another account or gateway'));
      await app.settle(t);

      expect(app.store.state.device.stage, UnlockStage.none);
      expect(app.store.state.login.password, isNull);
      expect(app.keys.has(app.store.state.device.keyId!), isTrue);
      expect(field('Gateway'), findsOneWidget);
      await app.leave(t);
    }, variant: mac);

    testWidgets('a removed device: signed out, the key deleted', (t) async {
      final app = await enrolled(t, FakeAnswer.sign);
      final alias = app.store.state.device.keyId;
      for (final d in app.gateway.records.values) {
        d.state = 'removed';
      }
      await app.pumpLogIn(t);

      expect(app.store.state.device.stage, UnlockStage.signedOut);
      expect(app.store.state.device.refusal, UnlockRefusal.removed);
      expect(app.store.state.session.token, isNull);
      expect(app.keys.has(alias!), isFalse);
      await app.leave(t);
    }, variant: mac);

    testWidgets('the fallback logs in with the password', (t) async {
      final app = await enrolled(t, FakeAnswer.cancelled);
      app.login.session.gateway.confirmed = false;
      await app.pumpLogIn(t);

      await t.enterText(input('Password for olena'), 'wrong');
      expect(app.store.state.login.password, 'wrong');
      await app.leave(t);
    }, variant: mac);
  });

  group('the idle lock', () {
    Future<LogInApp> locked(WidgetTester t, {bool key = true}) async {
      final app = LogInApp();
      if (key) {
        await app.enroll(t);
      }
      await app.logIn(t);
      app.store.dispatchSync(LockAction());
      await app.pumpLock(t);
      expect(app.store.state.device.locked, isTrue);
      return app;
    }

    testWidgets('a wrong password says so; the right one unlocks', (t) async {
      final app = await locked(t, key: false);

      await t.enterText(input('Password for olena'), 'nope');
      await t.tap(find.text('Unlock'));
      await app.settle(t);
      expect(app.store.state.device.locked, isTrue);
      expect(find.text(S.current.lockWrongPassword), findsOneWidget);

      await t.enterText(input('Password for olena'), password);
      await t.tap(find.text('Unlock'));
      await app.settle(t);
      expect(app.store.state.device.locked, isFalse);
      expect(app.store.state.session.token, isNotNull);
      expect(find.text('Studio is locked'), findsNothing);
      await app.leave(t);
    }, variant: mac);

    testWidgets('the key unlocks the same session, with its words', (
      t,
    ) async {
      final app = await locked(t);
      final logins = app.gateway.logins;

      await t.tap(find.byType(UnlockButton));
      await app.settle(t);

      expect(app.keys.reasons, ['sign in to plant as olena']);
      expect(app.gateway.logins, logins + 1);
      expect(app.store.state.device.locked, isFalse);
      expect(app.store.state.session.token, isNotNull);
      await app.leave(t);
    }, variant: mac);
  });

  group('the step-up', () {
    Future<(LogInApp, Future<void>)> refused(WidgetTester t) async {
      final app = LogInApp();
      await app.enroll(t);
      await app.logIn(t);
      final api = app.login.session.api
        ..stepUp = app.gateway
        ..stepUpKeys.add('wy/plant/sys/x');
      app.gateway.confirmed = false;
      final set = depsOf(app.store).wyrm.set('wy/plant/sys/x', const VInt(1));
      await t.runAsync(pumpEventQueue);
      expect(api.stepUp, isNotNull);
      await app.pumpStepUp(t);
      expect(app.store.state.device.stepUp, isNotNull);
      return (app, set);
    }

    int sets(LogInApp app) =>
        app.login.session.api.calls.where((c) => c.op == 'set').length;

    testWidgets('the key confirms; the request goes again', (t) async {
      final (app, set) = await refused(t);

      await t.tap(find.text('Confirm with Touch ID'));
      await app.settle(t);
      await t.runAsync(() => set);

      expect(app.keys.reasons, ['confirm changes on plant']);
      expect(app.gateway.confirms, 1);
      expect(sets(app), 2, reason: 'refused, then sent again');
      expect(app.store.state.device.stepUp, isNull);
      await app.leave(t);
    }, variant: mac);

    testWidgets('a wrong password stays; the right one confirms', (t) async {
      final (app, set) = await refused(t);
      await t.tap(find.text('Use the password'));
      await app.settle(t);

      await t.enterText(input('Password for olena'), 'nope');
      await t.tap(find.text('Confirm'));
      await app.settle(t);
      // The dialog stays with the refusal; the field does not show its
      // line today (the device row, which does, is hidden while the
      // password is asked for).
      expect(app.store.state.device.stepUp, isNotNull);
      expect(app.gateway.confirms, 0);
      expect(app.stepUpWords(t), contains('Password for olena'));

      await t.enterText(input('Password for olena'), password);
      await t.tap(find.text('Confirm'));
      await app.settle(t);
      await t.runAsync(() => set);
      expect(app.store.state.device.stepUp, isNull);
      expect(sets(app), 2);
      await app.leave(t);
    }, variant: mac);

    testWidgets('Cancel fails the request with the refusal', (t) async {
      final (app, set) = await refused(t);
      Object? failed;
      final done = set.catchError((Object e) => failed = e);

      await t.tap(find.text('Cancel'));
      await app.settle(t);
      await t.runAsync(() => done);

      expect(
        failed,
        isA<WyrmException>().having((e) => e.code, 'code', 'confirm_required'),
      );
      expect(app.store.state.device.stepUp, isNull);
      expect(sets(app), 1);
      await app.leave(t);
    }, variant: mac);
  });
}

/// A launcher that remembers what it was asked to open.
final class _Launcher extends UrlLauncherPlatform {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}
