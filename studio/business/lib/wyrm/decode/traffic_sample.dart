import 'package:models/live_value.dart';
import 'package:models/traffic_sample.dart';

import 'decoded.dart';

/// One [TrafficSample] from the live values of the six rate keys of `sys`
/// (`messages_in_per_second`, `messages_out…`, `frames_in…`,
/// `frames_out…`, `data_in…`, `data_out…`, in that order), at the newest
/// of their times. Null (valid) while one has not arrived; a value that is
/// not a number is [Invalid] with its key.
Decoded<TrafficSample?> trafficSampleOf(List<(String, LiveValue?)> rates) {
  final n = <double>[];
  for (final (key, v) in rates) {
    switch (v?.value) {
      case null:
        return const Valid(null);
      case final num x:
        n.add(x.toDouble());
      default:
        return Invalid('sys', key, 'not a number');
    }
  }
  if (n.length != 6) {
    return const Invalid('sys', '', 'not six rates');
  }
  final time = rates
      .map((r) => r.$2!.time)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return Valid(
    TrafficSample(
      time: time,
      messagesIn: n[0],
      messagesOut: n[1],
      framesIn: n[2],
      framesOut: n[3],
      dataIn: n[4],
      dataOut: n[5],
    ),
  );
}
