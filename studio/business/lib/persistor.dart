import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:models/panel_slot.dart';
import 'package:storage/storage.dart';

import 'redux/app_state.dart';
import 'redux/language/models/language_state.dart';
import 'redux/login/models/login_state.dart';
import 'redux/panels/models/panels_state.dart';
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

  /// One storage key per side panel. Spelled out rather than taken from
  /// `PanelSlot.name`, so renaming a slot does not drop what users stored.
  static const Map<PanelSlot, String> _panelKeys = {
    PanelSlot.explorerTree: 'panelWidth.explorer.tree',
    PanelSlot.explorerInspector: 'panelWidth.explorer.inspector',
    PanelSlot.flowPalette: 'panelWidth.flowEditor.palette',
    PanelSlot.flowInspector: 'panelWidth.flowEditor.inspector',
    PanelSlot.historyGroups: 'panelWidth.history.groups',
    PanelSlot.historyInspector: 'panelWidth.history.inspector',
  };

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
    final widths = <PanelSlot, double>{};
    for (final MapEntry(key: slot, value: key) in _panelKeys.entries) {
      if (_width(await _storage.get<Object?>(key)) case final w?) {
        widths[slot] = w;
      }
    }

    if (themeIndex == null &&
        locale == null &&
        gateway == null &&
        user == null &&
        widths.isEmpty) {
      return null;
    }

    return AppState.initial().copyWith(
      theme: ThemeState(
        mode: ThemeMode.values[themeIndex ?? ThemeMode.dark.index],
      ),
      language: LanguageState(locale: locale ?? 'en'),
      login: LoginState(gateway: gateway, user: user),
      panels: PanelsState(widths: widths.lock),
    );
  }

  /// A stored width, or null when it is missing or not a usable number.
  static double? _width(Object? v) =>
      v is num && v.isFinite && v > 0 ? v.toDouble() : null;

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

    final before = lastPersistedState?.panels.widths;
    final now = newState.panels.widths;
    if (before != now) {
      for (final MapEntry(key: slot, value: key) in _panelKeys.entries) {
        final w = now[slot];
        if (w != before?[slot]) {
          await (w == null ? _storage.delete(key) : _storage.put(key, w));
        }
      }
    }
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
    for (final key in _panelKeys.values) _storage.delete(key),
  ]);
}
