import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/theme/actions/set_theme_mode_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

import '../common/validators.dart';

@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LogInPage(
      gateway: vm.gateway,
      user: vm.user,
      password: vm.password,
      isWaiting: vm.isWaiting,
      onPressedLogIn: vm.onPressedLogIn,
      theme: vm.theme,
      language: vm.language,
    ),
  );
}

/// The gateway of the demo's central site (examples/demo/run.sh).
const defaultGateway = 'http://127.0.0.1:8445';

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    // The last gateway this user logged in to, else the demo's central site.
    gateway: FieldVm(
      value: login.gateway ?? defaultGateway,
      validator: gatewayValidator,
      onChanged: (v) => dispatchSync(SetGatewayAction(v)),
      enabled: !login.isWaiting,
    ),
    user: FieldVm(
      value: login.user,
      validator: (v) => requiredValidator(v),
      onChanged: (v) => dispatchSync(SetUserAction(v)),
      enabled: !login.isWaiting,
    ),
    // A gateway password has no shape rules here: the administrator who made
    // the user chose it, and the gateway is the one that checks it.
    password: FieldVm(
      value: login.password,
      validator: (v) => requiredValidator(v),
      onChanged: (v) => dispatchSync(SetPasswordAction(v)),
      enabled: !login.isWaiting,
    ),
    isWaiting: login.isWaiting,
    onPressedLogIn: () async {
      // The default shown in the field is only a hint until it is written.
      if (login.gateway == null) {
        dispatchSync(SetGatewayAction(defaultGateway));
      }
      await dispatchAndWait(LogInAction());
    },
    theme: FieldVm(
      value: theme.mode,
      onChanged: (mode) => dispatchSync(SetThemeModeAction(mode)),
    ),
    // The dispatch the language slice never had. `AppState.language` was
    // persisted, selected and read by `MaterialApp.locale` — and nothing
    // anywhere sent `SetLanguageAction`, so the app restored a language it
    // could not be told to change.
    language: FieldVm(
      value: language.locale,
      onChanged: (locale) => dispatchSync(SetLanguageAction(locale)),
    ),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.gateway,
    required this.user,
    required this.password,
    required this.isWaiting,
    required this.onPressedLogIn,
    required this.theme,
    required this.language,
  }) : super(equals: [gateway, user, password, isWaiting, theme, language]);

  final FieldVm<String?> gateway;
  final FieldVm<String?> user;
  final FieldVm<String?> password;
  final bool isWaiting;
  final VoidCallback onPressedLogIn;
  final FieldVm<ThemeMode> theme;
  final FieldVm<String> language;
}
