import 'package:app/navigation/leave_on_log_out_action.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/assistant_app.dart';

/// `Sign out everywhere` and the other log-outs go to the log-in page only
/// when the business action really ended the session.
void main() {
  test(
    'the session ended: it goes to log-in, after the inner action',
    () async {
      final log = <String>[];
      final s = fakeStore(
        initial: AppState.initial().copyWith.session(token: 't'),
      );
      await s.dispatchAndWait(
        LeaveOnLogOutAction(_EndSession(log), leave: () => _Went(log)),
      );
      expect(s.state.session.token, isNull);
      expect(log, ['ended', 'went to log-in']);
    },
  );

  test('the session is still there: it stays', () async {
    final log = <String>[];
    final s = fakeStore(
      initial: AppState.initial().copyWith.session(token: 't'),
    );
    await s.dispatchAndWait(
      LeaveOnLogOutAction(_Keep(log), leave: () => _Went(log)),
    );
    expect(log, ['kept']);
  });
}

class _EndSession extends ReduxAction<AppState> {
  _EndSession(this.log);
  final List<String> log;

  @override
  Future<AppState?> reduce() async {
    log.add('ended');
    return state.copyWith.session(token: null);
  }
}

class _Keep extends ReduxAction<AppState> {
  _Keep(this.log);
  final List<String> log;

  @override
  AppState? reduce() {
    log.add('kept');
    return null;
  }
}

class _Went extends ReduxAction<AppState> {
  _Went(this.log);
  final List<String> log;

  @override
  AppState? reduce() {
    log.add('went to log-in');
    return null;
  }
}
