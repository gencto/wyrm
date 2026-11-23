import 'package:models/live_value.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';

/// A sample of `subscribe` as a [LiveValue].
///
/// Not a typed decoder yet: [LiveValue.value] is the plain Dart of
/// [toDart], which its readers decode again (`plainValueOf`, `liveJsonOf`).
/// `tool/check_rules.dart` counts this file (`untyped-wire`, `still`) until
/// that value has a type.
LiveValue liveValueOf(Sample s) => LiveValue(
  value: toDart(s.v),
  quality: switch (s.q) {
    Quality.good => m.Quality.good,
    Quality.uncertain => m.Quality.uncertain,
    Quality.bad => m.Quality.bad,
  },
  time: DateTime.fromMicrosecondsSinceEpoch(s.t, isUtc: true),
);
