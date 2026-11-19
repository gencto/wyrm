import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// What an older Studio kept as typed (`user:password@` in the gateway
/// field and the recent gateways) is read clean and written back clean at
/// once; nothing written from now on holds credentials.
void main() {
  test('an older file is read clean and written back clean', () async {
    final settings = InMemoryKeyValueStorage();
    await settings.put(
      'gateway',
      'https://olena:gw-pass@plant.local:8445, u@edge:8446',
    );
    await settings.put(
      'recentGateways',
      'https://olena:gw-pass@plant.local:8445\nhttp://a:8445',
    );
    final read = await AppPersistor(settings).readState();
    expect(read!.login.gateway, 'https://plant.local:8445, edge:8446');
    expect(read.login.recent, ['https://plant.local:8445', 'http://a:8445']);
    // on disk at once, not only in the state
    expect(
      await settings.get<String>('gateway'),
      'https://plant.local:8445, edge:8446',
    );
    expect(
      await settings.get<String>('recentGateways'),
      'https://plant.local:8445\nhttp://a:8445',
    );
  });

  test('a clean file is left as it was', () async {
    final settings = InMemoryKeyValueStorage();
    await settings.put('gateway', 'http://a:8445');
    final read = await AppPersistor(settings).readState();
    expect(read!.login.gateway, 'http://a:8445');
    expect(await settings.get<String>('gateway'), 'http://a:8445');
  });

  test('a field typed with credentials is not written; the recent are '
      'written without them', () async {
    final settings = InMemoryKeyValueStorage();
    final state = AppState.initial().copyWith.login(
      gateway: 'https://olena:gw-pass@plant.local:8445',
      recent: ['https://u:p@b:8445'].lock,
    );
    await AppPersistor(settings).persistDifference(newState: state);
    expect(await settings.get<String>('gateway'), isNull);
    expect(await settings.get<String>('recentGateways'), 'https://b:8445');
  });

  test(
    'a field is kept only while it holds addresses alone: no part of a '
    'password typed in it reaches the disk (final audit of #137, 1)',
    () async {
      final settings = InMemoryKeyValueStorage();
      final persistor = AppPersistor(settings);
      AppState typed(String field) =>
          AppState.initial().copyWith.login(gateway: field);
      var last = typed('https://plant.local:8445');
      await persistor.persistDifference(newState: last);
      expect(await settings.get<String>('gateway'), 'https://plant.local:8445');
      for (final field in [
        'https://admin:pa ss@plant.local:8445',
        'https://admin:p@ss@plant.local:8445',
        'admin:secret@plant.local:8445',
        'https://admin:secret@plant.local:8445, edge:8446',
        'https://admin:s@',
      ]) {
        final now = typed(field);
        await persistor.persistDifference(
          lastPersistedState: last,
          newState: now,
        );
        last = now;
        // the last clean field stays; nothing of the password is written
        expect(
          await settings.get<String>('gateway'),
          'https://plant.local:8445',
          reason: field,
        );
      }
      final clean = typed('https://plant.local:8445, edge:8446');
      await persistor.persistDifference(
        lastPersistedState: last,
        newState: clean,
      );
      expect(
        await settings.get<String>('gateway'),
        'https://plant.local:8445, edge:8446',
      );
    },
  );

  test('an older value is cleaned up to its last @, with or without a '
      'scheme', () {
    expect(
      gatewayFieldWithoutCredentials('https://admin:p@ss@plant.local:8445'),
      'https://plant.local:8445',
    );
    expect(
      gatewayFieldWithoutCredentials('https://admin:pa ss@plant.local:8445'),
      'https://plant.local:8445',
    );
    expect(
      gatewayFieldWithoutCredentials(' admin:secret@plant.local:8445,b:1'),
      ' plant.local:8445,b:1',
    );
    expect(
      gatewayFieldWithoutCredentials('https://plant.local:8445/a@b'),
      'https://plant.local:8445/a@b',
    );
  });
}
