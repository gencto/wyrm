import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/dependencies.dart';
import 'package:business/environment.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_pretty_logging/pro_pretty_logging.dart';

import 'app.dart';
import 'common/window.dart';
import 'errors.dart';
import 'faults.dart';
import 'navigation/app_router.dart';
import 'start_fault_app.dart';

bool get isDesktop =>
    [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ].contains(defaultTargetPlatform) &&
    !kIsWeb;

Future<void> runEnv(Environment env) async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
    ),
  );

  prettyLogging(enable: kDebugMode);

  // Studio's own settings do not open: the start screen, and nothing else
  // of the app (docs/design/specs/errors.md §6). Fresh settings start it
  // again from here.
  final Store<AppState> store;
  try {
    store = await createStore(env, wording: wordError);
  } on StorageFault catch (fault) {
    debugPrint('settings did not open: $fault');
    if (isDesktop) {
      await setUpPlainWindow();
    }
    runApp(StartFaultApp(fault: fault, onFresh: () => runEnv(env)));
    return;
  }

  installFaultHooks(store);

  await (store.dependencies! as AppDependencies).warmUp();

  final appRouter = createAppRouter(store);

  // ExceptionDialog sits above the router's Navigator (in the MaterialApp
  // builder), so its dialogs need a context *inside* the Navigator. Hand
  // async_redux the router's navigator key so it can find one.
  NavigateAction.setNavigatorKey(appRouter.navigatorKey);

  // Re-run the auth guard whenever the logged-in state flips, so login/logout
  // bounces the user to the right area — the auto_route analogue of
  // go_router's `refreshListenable`.
  final routerConfig = appRouter.config(
    reevaluateListenable: ReevaluateListenable.stream(
      // The same selector the guard decides on, so the two cannot drift.
      store.onChange
          .map((state) => SelectSession(state).isAvailable)
          .distinct(),
    ),
  );

  if (isDesktop) {
    await setUpWindow(store);
  }

  runApp(
    StoreProvider(
      store: store,
      child: AppConnector(routerConfig: routerConfig),
    ),
  );
}
