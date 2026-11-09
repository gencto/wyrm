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
/// last gateway URL and user, the recent gateways, the Remember choice and
/// the side panels' widths) is stored — not the whole state. With Remember
/// off, the gateway, the user and the recent gateways are deleted and not
/// written again
/// (docs/design/specs/login.md §6).
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
  static const _recentKey = 'recentGateways';
  static const _rememberKey = 'remember';

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
    final recent = await _storage.get<String>(_recentKey);
    final remember = await _storage.get<bool>(_rememberKey);
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
        recent == null &&
        remember == null &&
        widths.isEmpty) {
      return null;
    }

    return AppState.initial().copyWith(
      theme: ThemeState(
        mode: ThemeMode.values[themeIndex ?? ThemeMode.dark.index],
      ),
      language: LanguageState(locale: locale ?? 'en'),
      login: LoginState(
        gateway: gateway,
        user: user,
        recent: _lines(recent),
        remember: remember ?? true,
      ),
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

    final before = lastPersistedState?.login;
    final now = newState.login;
    if (before?.remember != now.remember) {
      await _storage.put(_rememberKey, now.remember);
    }
    // Remember off: what was kept goes, and nothing is written in its place.
    final kept = before == null || before.remember;
    await _putOrDelete(
      _gatewayKey,
      kept ? before?.gateway : null,
      now.remember ? now.gateway : null,
    );
    await _putOrDelete(
      _userKey,
      kept ? before?.user : null,
      now.remember ? now.user : null,
    );
    await _putOrDelete(
      _recentKey,
      kept ? _joined(before?.recent) : null,
      now.remember ? _joined(now.recent) : null,
    );

    final widthsBefore = lastPersistedState?.panels.widths;
    final widths = newState.panels.widths;
    if (widthsBefore != widths) {
      for (final MapEntry(key: slot, value: key) in _panelKeys.entries) {
        final w = widths[slot];
        if (w != widthsBefore?[slot]) {
          await (w == null ? _storage.delete(key) : _storage.put(key, w));
        }
      }
    }
  }

  /// The recent gateways, one per line (a gateway is itself a comma list).
  static String? _joined(IList<String>? recent) =>
      recent == null || recent.isEmpty ? null : recent.join('\n');

  static IList<String> _lines(String? text) => text == null
      ? const IListConst([])
      : [
          for (final l in text.split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ].lock;

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
    _storage.delete(_recentKey),
    _storage.delete(_rememberKey),
    _storage.delete(_legacyTokenKey),
    for (final key in _panelKeys.values) _storage.delete(key),
  ]);
}
