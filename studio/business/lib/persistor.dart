import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';
import 'package:storage/storage.dart';

import 'redux/app_state.dart';
import 'redux/language/models/language_state.dart';
import 'redux/login/models/login_state.dart';
import 'redux/theme/models/theme_state.dart';

/// AsyncRedux [Persistor] backed by the `storage` package ([KeyValueStorage]).
///
/// The store calls [persistDifference] (throttled) after state changes and
/// [readState] once on boot. Only the persisted slice (theme, language, the
/// last gateway URL and user) is stored — not the whole state.
///
/// The session token is not stored: a gateway session lives in the WebSocket
/// client of `AppDependencies`, which a restart does not bring back, so a
/// restored token would let the user into screens with no broker behind them.
/// The password is never stored (docs/studio.md §5.1).
class AppPersistor extends Persistor<AppState> {
  AppPersistor(this._storage);

  final BaseKeyValueStorage _storage;

  static const _themeKey = 'themeMode';
  static const _localeKey = 'locale';
  static const _gatewayKey = 'gateway';
  static const _userKey = 'user';

  /// The key older builds kept the session token under; deleted on boot.
  static const _legacyTokenKey = 'token';

  @override
  Duration? get throttle => const Duration(seconds: 1);

  @override
  Future<AppState?> readState() async {
    final themeIndex = await _storage.get<int>(_themeKey);
    final locale = await _storage.get<String>(_localeKey);
    final gateway = await _storage.get<String>(_gatewayKey);
    final user = await _storage.get<String>(_userKey);
    await _storage.delete(_legacyTokenKey);

    if (themeIndex == null &&
        locale == null &&
        gateway == null &&
        user == null) {
      return null;
    }

    return AppState.initial().copyWith(
      theme: ThemeState(
        mode: ThemeMode.values[themeIndex ?? ThemeMode.dark.index],
      ),
      language: LanguageState(locale: locale ?? 'en'),
      login: LoginState(gateway: gateway, user: user),
    );
  }

  @override
  Future<void> persistDifference({
    required AppState newState,
    AppState? lastPersistedState,
  }) async {
    if (lastPersistedState?.theme != newState.theme) {
      await _storage.put(_themeKey, newState.theme.mode.index);
    }

    if (lastPersistedState?.language != newState.language) {
      await _storage.put(_localeKey, newState.language.locale);
    }

    await _putOrDelete(
      _gatewayKey,
      lastPersistedState?.login.gateway,
      newState.login.gateway,
    );
    await _putOrDelete(
      _userKey,
      lastPersistedState?.login.user,
      newState.login.user,
    );
  }

  Future<void> _putOrDelete(String key, String? before, String? now) async {
    if (before == now) {
      return;
    }
    await (now == null ? _storage.delete(key) : _storage.put(key, now));
  }

  @override
  Future<void> deleteState() => Future.wait([
    _storage.delete(_themeKey),
    _storage.delete(_localeKey),
    _storage.delete(_gatewayKey),
    _storage.delete(_userKey),
    _storage.delete(_legacyTokenKey),
  ]);
}
