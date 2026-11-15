import 'package:app/common/app_store.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/lock_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:ui/buttons/unlock_button.dart';
import 'package:ui/inputs/boxed_form_field.dart';
import 'package:ui/theme/common.dart';

import 'support/log_in_app.dart';

/// The log-in page leaves for Studio, and the lock back to it, through the
/// app's own router (studio-rules, step 1): read from the route on screen,
/// the store, the fake gateway and the key store. One test, because the
/// router is built once per file.
void main() {
  setUpAll(loadFonts);

  testWidgets(
    'log in, the offer, Studio; the lock, the key, a refused key',
    (t) async {
      await S.load(const Locale('en'));
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = LogInApp()
        ..put(
          (a) =>
              a.copyWith.login(gateway: gw, user: 'ivan', password: password),
        );
      final store = app.store;
      createAppRouter(store);
      await t.pumpWidget(
        StoreProvider<AppState>(
          store: store,
          child: AppStore(
            store: store,
            child: MaterialApp.router(
              routerConfig: appRouter.config(
                reevaluateListenable: ReevaluateListenable.stream(
                  store.onChange
                      .map((s) => SelectSession(s).isAvailable)
                      .distinct()
                      .where((available) => !available),
                ),
              ),
              theme: darkTheme(),
              // The app's builder puts no Material above the router, and
              // the lock card's password field asks for one in a debug
              // build: given here until the card has its own.
              builder: (context, child) => Material(
                type: MaterialType.transparency,
                child: child,
              ),
              localizationsDelegates: const [
                S.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
            ),
          ),
        ),
      );
      await app.settle(t);
      String route() => appRouter.topRoute.name;
      bool inStudio() => appRouter.stack.any((r) => r.name == StudioRoute.name);
      Finder input(String label) => find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is BoxedFormField && w.label == label,
            ),
            matching: find.byType(EditableText),
          )
          .hitTestable();
      Future<void> logInButton() async {
        await t.pump(const Duration(seconds: 2));
        await t.tap(find.widgetWithText(InkWell, 'Log in').hitTestable().last);
        await app.settle(t);
      }

      Future<void> lockAndLogOut() async {
        store.dispatchSync(LockAction());
        await app.settle(t);
        expect(find.text('Studio is locked'), findsOneWidget);
        await t.tap(find.text('Log out'));
        await app.settle(t);
      }

      expect(route(), LogInRoute.name);

      // 1. A password log-in offers the key; Not now opens Studio.
      await logInButton();
      expect(store.state.session.token, isNotNull);
      expect(store.state.device.stage, UnlockStage.offer);
      expect(route(), LogInRoute.name, reason: 'the offer waits');
      await t.tap(find.text('Not now'));
      await app.settleWelcome(t);
      expect(inStudio(), isTrue, reason: route());
      expect(store.state.device.offered, isTrue);
      expect(store.state.device.dontAsk, isFalse);
      expect(store.state.device.keyId, isNull);

      // 2. The lock's Log out goes back to the log-in page.
      await lockAndLogOut();
      expect(store.state.session.token, isNull);
      expect(route(), LogInRoute.name);

      // 3. Asked once: the next log-in goes straight to Studio.
      await t.enterText(input('Password'), password);
      await logInButton();
      await app.settleWelcome(t);
      expect(inStudio(), isTrue, reason: route());
      await lockAndLogOut();

      // 4. Another user: Don't ask on this computer opens Studio.
      await t.enterText(input('User'), 'petro');
      await t.enterText(input('Password'), password);
      await logInButton();
      expect(store.state.device.stage, UnlockStage.offer);
      await t.tap(find.text('Don’t ask on this computer'));
      await app.settleWelcome(t);
      expect(inStudio(), isTrue, reason: route());
      expect(store.state.device.dontAsk, isTrue);
      await lockAndLogOut();

      // 5. Another user: Use Touch ID makes the key, with its words.
      await t.enterText(input('User'), user);
      await t.enterText(input('Password'), password);
      await logInButton();
      expect(store.state.device.stage, UnlockStage.offer);
      app.keys.reasons.clear();
      await t.tap(find.text('Use Touch ID'));
      await app.settleWelcome(t);
      expect(app.keys.reasons, ['turn on unlocking plant as olena']);
      expect(store.state.device.deviceId, isNotNull);
      expect(app.gateway.records, hasLength(1));
      expect(inStudio(), isTrue, reason: route());

      // 6. The lock opens with the key and keeps the session.
      store.dispatchSync(LockAction());
      await app.settle(t);
      app.keys.reasons.clear();
      await t.tap(find.byType(UnlockButton));
      await app.settle(t);
      expect(app.keys.reasons, ['sign in to plant as olena']);
      expect(store.state.device.locked, isFalse);
      expect(inStudio(), isTrue, reason: route());

      // 7. Logged out, the page shows the key (its own prompt ran once this
      // start); the round button unlocks into Studio.
      await lockAndLogOut();
      expect(store.state.device.stage, UnlockStage.unlock);
      app.keys.reasons.clear();
      await t.tap(find.byType(UnlockButton));
      await app.settleWelcome(t);
      expect(app.keys.reasons, ['sign in to plant as olena']);
      expect(store.state.session.token, isNotNull);
      expect(inStudio(), isTrue, reason: route());

      // 8. A key the gateway removed: the lock leaves for the log-in page,
      // which says why; the key is gone.
      final alias = store.state.device.keyId!;
      for (final d in app.gateway.records.values) {
        d.state = 'removed';
      }
      store.dispatchSync(LockAction());
      await app.settle(t);
      await t.tap(find.byType(UnlockButton));
      await app.settle(t);
      expect(store.state.session.token, isNull);
      expect(route(), LogInRoute.name);
      expect(store.state.device.stage, UnlockStage.signedOut);
      expect(store.state.device.refusal, UnlockRefusal.removed);
      expect(app.keys.has(alias), isFalse);
      expect(find.text('Removed by an administrator'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await app.settle(t);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
