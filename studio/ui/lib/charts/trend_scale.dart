import 'dart:math' as math;

import 'trend.dart';

/// The geometry of a [Trend] (spec `docs/design/specs/trend.md` §1, §3, §4):
/// pure functions of its data, so they are tested without a widget.

/// A Y axis that fits [lo]…[hi] with a step of 1, 2, 2.5 or 5 × 10ⁿ
/// (3–5 ticks).
final class TrendAxis {
  const TrendAxis(this.lo, this.hi, this.step);

  /// The axis over the values [lo]…[hi]; `0…100` when there are none.
  factory TrendAxis.fit(double lo, double hi) {
    if (!lo.isFinite || !hi.isFinite) {
      return const TrendAxis(0, 100, 25);
    }
    final raw = (hi - lo) / 3;
    final r = raw > 0 ? raw : (lo.abs() > 0 ? lo.abs() / 10 : 1);
    final mag = math.pow(10, (math.log(r) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10]
        .map((k) => k * mag)
        .firstWhere((k) => k >= r - 1e-12, orElse: () => 10 * mag);
    var a = (lo / step).floorToDouble() * step;
    var b = (hi / step).ceilToDouble() * step;
    if (b - a < step / 2) {
      a -= step;
      b += step;
    }
    return TrendAxis(a, b, step);
  }

  final double lo;
  final double hi;
  final double step;

  List<double> get ticks => [
    for (var v = lo; v <= hi + step * 1e-6; v += step) v,
  ];

  /// The y of [v] on a plot [height] high (4 px inset at both ends).
  double y(double v, double height) =>
      height - 4 - (v - lo) / (hi - lo) * (height - 8);

  /// [v] with the decimals the step needs (`80`, `82.5`, `0.25`).
  String label(double v) {
    var d = 0;
    while (d < 6) {
      final s = step * math.pow(10, d);
      if ((s - s.roundToDouble()).abs() < 1e-6) {
        break;
      }
      d++;
    }
    final t = v.toStringAsFixed(d);
    return t == '-0' ? '0' : t;
  }

  @override
  bool operator ==(Object other) =>
      other is TrendAxis &&
      other.lo == lo &&
      other.hi == hi &&
      other.step == step;

  @override
  int get hashCode => Object.hash(lo, hi, step);
}

/// A stretch of a line drawn one way: solid, or dashed for `uncertain`.
final class TrendRun {
  const TrendRun(this.points, {required this.dashed});

  final List<TrendSample> points;
  final bool dashed;
}

/// A stretch without a drawable row longer than two buckets, from the last
/// row drawn before it to the first after it. [bad] when the stretch holds
/// rows of quality `bad` (recorded, not drawn).
final class TrendGap {
  const TrendGap(this.from, this.to, {this.bad = false});

  final int from;
  final int to;
  final bool bad;

  @override
  bool operator ==(Object other) =>
      other is TrendGap &&
      other.from == from &&
      other.to == to &&
      other.bad == bad;

  @override
  int get hashCode => Object.hash(from, to, bad);

  @override
  String toString() => 'TrendGap($from, $to${bad ? ', bad' : ''})';
}

/// The lines and the gaps of one series.
final class TrendTrace {
  const TrendTrace(this.runs, this.gaps);

  final List<TrendRun> runs;
  final List<TrendGap> gaps;
}

/// A row that is drawn: a value, and not `bad`.
bool drawable(TrendSample s) => s.v != null && s.q != .bad;

/// The usual distance between the drawable rows of [samples] (the median),
/// or null with fewer than two.
int? spacing(List<TrendSample> samples) {
  final d = <int>[];
  TrendSample? p;
  for (final s in samples) {
    if (!drawable(s)) {
      continue;
    }
    if (p != null && s.t > p.t) {
      d.add(s.t - p.t);
    }
    p = s;
  }
  if (d.isEmpty) {
    return null;
  }
  d.sort();
  return d[d.length ~/ 2];
}

/// Splits [samples] (oldest first) into runs and gaps. A gap is longer than
/// two buckets of [step] (the median spacing of the rows without one); a
/// change between `good` and `uncertain` starts a new run from the last
/// point, so the line stays joined.
TrendTrace trace(List<TrendSample> samples, int? step) {
  final runs = <TrendRun>[];
  final gaps = <TrendGap>[];
  final b = step ?? spacing(samples);
  if (b == null) {
    return TrendTrace(runs, gaps);
  }
  final limit = 2 * b;
  var run = <TrendSample>[];
  var dashed = false;
  TrendSample? prev;
  var badSince = false;
  void flush() {
    if (run.length > 1) {
      runs.add(TrendRun(run, dashed: dashed));
    }
    run = <TrendSample>[];
  }

  for (final s in samples) {
    if (!drawable(s)) {
      if (s.q == .bad) {
        badSince = true;
      }
      continue;
    }
    final unc = s.q == .uncertain;
    if (prev != null && s.t - prev.t > limit) {
      gaps.add(TrendGap(prev.t, s.t, bad: badSince));
      flush();
      dashed = unc;
    } else if (run.isNotEmpty && unc != dashed) {
      final last = run.last;
      flush();
      run.add(last);
      dashed = unc;
    } else if (run.isEmpty) {
      dashed = unc;
    }
    run.add(s);
    prev = s;
    badSince = false;
  }
  flush();
  return TrendTrace(runs, gaps);
}

/// Overlapping gaps merged into one band each, oldest first.
List<TrendGap> unionOf(Iterable<TrendGap> gaps) {
  final all = gaps.toList()..sort((a, b) => a.from.compareTo(b.from));
  final out = <TrendGap>[];
  for (final g in all) {
    if (out.isNotEmpty && g.from <= out.last.to) {
      final l = out.removeLast();
      out.add(
        TrendGap(l.from, math.max(l.to, g.to), bad: l.bad || g.bad),
      );
    } else {
      out.add(g);
    }
  }
  return out;
}

/// The index of the row of [samples] nearest to [t] (sorted by time), or
/// -1 when none is within [tolerance].
int nearest(List<TrendSample> samples, int t, int tolerance) {
  if (samples.isEmpty) {
    return -1;
  }
  var lo = 0;
  var hi = samples.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (samples[mid].t < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  var best = lo;
  if (lo > 0 && (t - samples[lo - 1].t).abs() <= (samples[lo].t - t).abs()) {
    best = lo - 1;
  }
  return (samples[best].t - t).abs() <= tolerance ? best : -1;
}

/// Where the crosshair stops near [t]: on the bucket grid of [step] that
/// starts at [anchor], or on the nearest row of [times] (sorted) without one.
int snap(int t, {int? step, int? anchor, List<int> times = const []}) {
  if (step != null && step > 0 && anchor != null) {
    return anchor + ((t - anchor) / step).round() * step;
  }
  if (times.isEmpty) {
    return t;
  }
  var lo = 0;
  var hi = times.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (times[mid] < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && (t - times[lo - 1]).abs() <= (times[lo] - t).abs()) {
    return times[lo - 1];
  }
  return times[lo];
}

/// [start]…[end] moved and clamped into [lo]…[hi], never narrower than
/// [min] (nor wider than the range).
(int, int) clampWindow(int start, int end, int lo, int hi, int min) {
  final full = hi - lo;
  var w = end - start;
  if (w < min) {
    w = math.min(min, full);
  }
  if (w > full) {
    w = full;
  }
  var a = start;
  if (end - start < min) {
    // Grown from its centre when it was too narrow.
    a = start + (end - start - w) ~/ 2;
  }
  if (a < lo) {
    a = lo;
  }
  if (a + w > hi) {
    a = hi - w;
  }
  return (a, a + w);
}

/// [start]…[end] zoomed by [factor] (> 1 out, < 1 in) around [at].
(int, int) zoomWindow(int start, int end, int at, double factor) {
  final a = at - ((at - start) * factor).round();
  final b = at + ((end - at) * factor).round();
  return (a, b);
}
