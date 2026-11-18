import 'package:business/redux/problems/actions/add_problem_action.dart';
import 'package:business/redux/problems/actions/report_problem_action.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';

import 'support/fake_wyrm.dart';

/// A fault no action caught is reported by the app's handlers, which wait
/// for nothing: each report is one change of the state, at once, and the
/// same fault again within two seconds changes nothing.
void main() {
  StudioError fault(String what, {String? panel}) =>
      faultOf(StateError(what), null, screen: panel);

  test('two faults reported in one turn are both in Problems, newest '
      'first', () {
    final s = fakeStore()
      ..dispatchSync(ReportProblemAction(fault('one')))
      ..dispatchSync(ReportProblemAction(fault('two')));
    expect(
      [for (final e in s.state.problems.items) e.report!.line],
      ['Bad state: two', 'Bad state: one'],
    );
  });

  test('two failures that are not faults of a part, with different keys, '
      'reported in one turn, are both kept (audit probe)', () {
    final s = fakeStore()
      ..dispatchSync(
        ReportProblemAction(
          const StudioError(kind: ErrorKind.studio, message: 'one', key: 'a'),
        ),
      )
      ..dispatchSync(
        ReportProblemAction(
          const StudioError(kind: ErrorKind.studio, message: 'two', key: 'b'),
        ),
      );
    expect([for (final e in s.state.problems.items) e.key], ['b', 'a']);
  });

  test('two parts that throw in turn are each held back within the '
      'window', () {
    final now = DateTime(2026, 11, 18, 12);
    final s = fakeStore(clock: () => now);
    for (var i = 0; i < 4; i++) {
      s
        ..dispatchSync(ReportProblemAction(fault('a', panel: 'Trend')))
        ..dispatchSync(ReportProblemAction(fault('b', panel: 'Log')));
    }
    expect(s.state.problems.items, hasLength(2));
  });

  test('a report keeps what changed in between', () {
    final s = fakeStore()
      ..dispatchSync(ReportProblemAction(fault('one')))
      ..dispatchSync(
        AddProblemAction(const StudioError(kind: ErrorKind.broker)),
      )
      ..dispatchSync(ReportProblemAction(fault('two')));
    expect(s.state.problems.items, hasLength(3));
  });

  test('the same fault within two seconds is taken once; after them, or '
      'another panel, again', () {
    var now = DateTime(2026, 11, 18, 12);
    final s = fakeStore(clock: () => now)
      ..dispatchSync(ReportProblemAction(fault('loop', panel: 'Trend')));
    final before = s.state;
    s.dispatchSync(ReportProblemAction(fault('loop', panel: 'Trend')));
    expect(identical(s.state, before), isTrue, reason: 'nothing to build');
    s.dispatchSync(ReportProblemAction(fault('loop', panel: 'Log')));
    expect(s.state.problems.items, hasLength(2));
    now = now.add(ReportProblemAction.repeatWithin);
    s.dispatchSync(ReportProblemAction(fault('loop', panel: 'Log')));
    expect(s.state.problems.items, hasLength(2), reason: 'one line, again');
    expect(s.state.problems.items.first.at, now);
  });
}
