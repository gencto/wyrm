import 'package:models/hist_point.dart';
import 'package:models/quality.dart' as studio;
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';

/// One history row (`~val?history=`, spec 01) as a point: a number when
/// the value is one (a bool as 0/1), the value as text, the quality only on
/// a raw row. A map, a list or bytes have no text, unless [wholeText] (the
/// Explorer's rows: written as plain Dart).
///
/// Every row is a point: a value of any type is one.
HistPoint histPointOf(HistRow r, {bool wholeText = false}) => HistPoint(
  time: DateTime.fromMicrosecondsSinceEpoch(r.t, isUtc: true),
  value:
      number(r.v) ??
      switch (r.v) {
        VBool(:final v) => v ? 1 : 0,
        _ => null,
      },
  text: text(r.v) ?? (wholeText ? '${toDart(r.v)}' : ''),
  quality: switch (r.q) {
    null => null,
    Quality.good => studio.Quality.good,
    Quality.uncertain => studio.Quality.uncertain,
    Quality.bad => studio.Quality.bad,
  },
);
