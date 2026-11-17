import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What [rebuilds] measured: how many of the runs built the widget again,
/// and the median wall time of one run (the dispatch and the two frames
/// that follow it).
typedef Rebuilds = ({int built, int runs, int medianUs});

/// Runs [change] [runs] times (with the run's index) and counts the runs
/// after which the one widget of type [W] is a new object: the connector
/// above it built it again. The store tells a connector in a microtask, so
/// the first frame may come before the new view-model: two frames hold all
/// of its work.
Future<Rebuilds> rebuilds<W extends Widget>(
  WidgetTester t,
  void Function(int i) change, {
  int runs = 50,
}) async {
  final us = <int>[];
  final watch = Stopwatch();
  var built = 0;
  for (var i = 0; i < runs; i++) {
    final before = t.widget(find.byType(W));
    watch
      ..reset()
      ..start();
    change(i);
    await t.pump();
    await t.pump();
    watch.stop();
    us.add(watch.elapsedMicroseconds);
    if (!identical(before, t.widget(find.byType(W)))) {
      built++;
    }
  }
  us.sort();
  return (built: built, runs: runs, medianUs: us[us.length ~/ 2]);
}

/// One line for the test's output: what ran, how often it built the
/// page, how long a run took.
void report(String what, Rebuilds r) => debugPrint(
  '$what: built ${r.built}/${r.runs}, median ${r.medianUs} µs per dispatch',
);
