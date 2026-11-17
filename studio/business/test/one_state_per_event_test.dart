import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/services/live_values/live_values_dispatcher.dart';
import 'package:business/redux/services/tree_watch/tree_watch_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// What a service hands the store (a batch of live values, up to five a
/// second; a failed subscription; a failed list) is one new state: each
/// connector on screen follows it once, never through the half-applied
/// states in between (studio-rules §9).
void main() {
  late Store<AppState> s;
  late List<AppState> changes;

  setUp(() {
    s = fakeStore();
    changes = [];
    // The states the connectors see: a new one, not the same one again
    // (an action that returns none still tells its listeners).
    var last = s.state;
    s.onChange.listen((now) {
      if (!identical(now, last)) {
        changes.add(now);
        last = now;
      }
    });
  });

  test('a batch of live values is one state', () async {
    LiveValuesDispatcher(store: s).onValues({
      'wy/central/downstream/m/a': LiveValue(time: DateTime(2026), value: 1),
      'wy/central/downstream/m/b': LiveValue(time: DateTime(2026), value: 2),
    });
    await pumpEventQueue();
    expect(changes, hasLength(1));
    expect(s.state.live.values.keys, hasLength(2));

    // a batch that changes nothing is no state at all
    LiveValuesDispatcher(store: s).onValues(const {});
    await pumpEventQueue();
    expect(changes, hasLength(1));
  });

  test('values of a site whose stream was down are one state with the '
      'stream back', () async {
    final d = LiveValuesDispatcher(store: s)
      ..onError(
        'wy/central/downstream/m/a',
        WyrmException.of(Status.closed, 'gone'),
      );
    await pumpEventQueue();
    expect(s.state.problems.toasts, isNotEmpty);
    changes.clear();
    d.onValues({
      'wy/central/downstream/m/a': LiveValue(time: DateTime(2026), value: 1),
    });
    await pumpEventQueue();
    expect(changes, hasLength(1));
    expect(s.state.problems.toasts, isEmpty);
  });

  test(
    'a failed subscription is one state: the mark and the problem',
    () async {
      LiveValuesDispatcher(store: s).onError(
        'wy/central/downstream/m/a',
        WyrmException.of(Status.internalError, 'boom'),
      );
      await pumpEventQueue();
      expect(changes, hasLength(1));
      expect(s.state.live.failed['wy/central/downstream/m/a'], isNotNull);
      expect(s.state.problems.items, hasLength(1));
    },
  );

  test(
    'a failed list is one state: no children, the mark, the problem',
    () async {
      TreeWatchDispatcher(store: s).onListError(
        'wy/central/downstream/m',
        WyrmException.of(Status.internalError, 'boom'),
      );
      await pumpEventQueue();
      expect(changes, hasLength(1));
      expect(s.state.nodes.listFailed['wy/central/downstream/m'], isNotNull);
      expect(s.state.problems.items, hasLength(1));
    },
  );
}
