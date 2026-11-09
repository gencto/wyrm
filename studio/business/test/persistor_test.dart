import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/panel_slot.dart';
import 'package:storage/storage.dart';

/// [AppPersistor] is the one module here that can silently lose a user's data,
/// and until `storage` exported its interface there was no way to run it: the
/// only adapter reached path_provider and a real file.
///
/// `InMemoryKeyValueStorage` is why this file exists. It is the second adapter
/// the seam was always shaped for.
void main() {
  late InMemoryKeyValueStorage storage;
  late AppPersistor persistor;

  setUp(() {
    storage = InMemoryKeyValueStorage();
    persistor = AppPersistor(storage);
  });

  group('readState', () {
    test(
      'an empty storage means no persisted state, not a default one',
      () =>
          // The distinction matters at boot: `createStore` falls back to
          // `AppState.initial()` on null. Returning a state here instead would
          // make the two paths indistinguishable.
          expectLater(persistor.readState(), completion(isNull)),
    );

    test('restores theme, language and the last gateway and user', () async {
      await storage.put('themeMode', ThemeMode.dark.index);
      await storage.put('locale', 'uk');
      await storage.put('gateway', 'http://127.0.0.1:8445');
      await storage.put('user', 'admin');

      final state = await persistor.readState();

      expect(state?.theme.mode, ThemeMode.dark);
      expect(state?.language.locale, 'uk');
      expect(state?.login.gateway, 'http://127.0.0.1:8445');
      expect(state?.login.user, 'admin');
    });

    test('never restores a session or a password', () async {
      // A session lives in the WebSocket client, which a restart does not
      // bring back; a restored token would open screens with no broker.
      await storage.put('token', 'tok');
      await storage.put('user', 'admin');

      final state = await persistor.readState();

      expect(state?.session.token, isNull);
      expect(state?.login.password, isNull);
      expect(
        storage.values.containsKey('token'),
        isFalse,
        reason: 'the key of older builds is deleted',
      );
    });

    test('one persisted key is enough to rebuild a state', () async {
      await storage.put('locale', 'uk');

      final state = await persistor.readState();

      expect(state, isNotNull);
      expect(state?.language.locale, 'uk');
      expect(state?.theme.mode, ThemeMode.dark, reason: 'falls back');
    });
  });

  group('persistDifference', () {
    test('writes every slice on the first pass', () async {
      await persistor.persistDifference(
        newState: AppState.initial().copyWith.login(user: 'admin'),
      );

      expect(storage.values.keys, containsAll(['themeMode', 'locale', 'user']));
    });

    test('writes nothing when nothing changed', () async {
      final state = AppState.initial().copyWith.login(user: 'admin');
      await persistor.persistDifference(newState: state);
      await storage.clear();

      await persistor.persistDifference(
        newState: state,
        lastPersistedState: state,
      );

      expect(storage.values, isEmpty);
    });

    test('writes only the value that changed', () async {
      final before = AppState.initial();
      await storage.clear();

      await persistor.persistDifference(
        newState: before.copyWith.language(locale: 'uk'),
        lastPersistedState: before,
      );

      expect(storage.values.keys, ['locale']);
    });

    test('a cleared value is deleted, not written as null', () async {
      await storage.put('user', 'admin');
      final before = AppState.initial().copyWith.login(user: 'admin');

      await persistor.persistDifference(
        newState: before.copyWith.login(user: null),
        lastPersistedState: before,
      );

      expect(storage.values.containsKey('user'), isFalse);
    });

    test('the password and the token are never written', () async {
      await persistor.persistDifference(
        newState: AppState.initial().copyWith
            .login(user: 'admin', password: 'secret')
            .copyWith
            .session(token: 'user:admin'),
      );

      expect(storage.values.values, isNot(contains('secret')));
      expect(storage.values.values, isNot(contains('user:admin')));
    });
  });

  group('panel widths', () {
    AppState withWidths(Map<PanelSlot, double> w) =>
        AppState.initial().copyWith.panels(widths: w.lock);

    test('round-trip through the storage', () async {
      final state = withWidths({
        PanelSlot.explorerTree: 340,
        PanelSlot.explorerInspector: 300.5,
        PanelSlot.flowPalette: 240,
      });
      await persistor.persistDifference(newState: state);

      expect(storage.values['panelWidth.explorer.tree'], 340);
      final read = await persistor.readState();

      expect(read?.panels.widths, state.panels.widths);
      expect(read?.panels.widths[PanelSlot.historyGroups], isNull);
    });

    test('widths alone are enough to rebuild a state', () async {
      await storage.put('panelWidth.history.groups', 300);

      final state = await persistor.readState();

      expect(state?.panels.widths[PanelSlot.historyGroups], 300.0);
      expect(state?.theme.mode, ThemeMode.dark, reason: 'falls back');
    });

    test('a bad stored width falls back to the default', () async {
      await storage.put('panelWidth.explorer.tree', 'wide');
      await storage.put('panelWidth.explorer.inspector', -20);
      await storage.put('panelWidth.flowEditor.palette', double.nan);
      await storage.put('locale', 'uk');

      final state = await persistor.readState();

      expect(state?.panels.widths, isEmpty);
    });

    test('writes only the width that changed', () async {
      final before = withWidths({PanelSlot.explorerTree: 300});
      await storage.clear();

      await persistor.persistDifference(
        newState: withWidths({
          PanelSlot.explorerTree: 300,
          PanelSlot.flowInspector: 400,
        }),
        lastPersistedState: before,
      );

      expect(storage.values, {'panelWidth.flowEditor.inspector': 400.0});
    });
  });

  group('deleteState', () {
    test('removes every key', () async {
      await storage.put('themeMode', 1);
      await storage.put('locale', 'uk');
      await storage.put('gateway', 'http://127.0.0.1:8445');
      await storage.put('user', 'admin');
      await storage.put('panelWidth.explorer.tree', 300);

      await persistor.deleteState();

      expect(storage.values, isEmpty);
    });
  });
}
