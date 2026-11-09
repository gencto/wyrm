import 'package:models/live_value.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// A sample of `subscribe` as a [LiveValue].
LiveValue liveValueOf(Sample s) => LiveValue(
  value: toDart(s.v),
  quality: switch (s.q) {
    Quality.good => m.Quality.good,
    Quality.uncertain => m.Quality.uncertain,
    Quality.bad => m.Quality.bad,
  },
  time: DateTime.fromMicrosecondsSinceEpoch(s.t, isUtc: true),
);
