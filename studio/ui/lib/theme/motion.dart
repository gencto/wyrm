import 'package:flutter/widgets.dart';

/// Motion tokens of the log-in board (docs/design/specs/login.md §4), taken
/// from the board's CSS — layer 3 of the theme strategy (see `common.dart`).
///
/// A CSS `@keyframes` rule eases each segment between two keyframes with the
/// element's timing function, not the whole run: [keyframes] does the same.
/// `ease-in-out` and `ease-out` are `Curves.easeInOut` and `Curves.easeOut`
/// exactly; a rule with no timing function uses CSS `ease`, `Curves.ease`.
abstract final class Motion {
  /// §4.1 packets on an edge; every odd edge [packetsSlow].
  static const packets = Duration(milliseconds: 4800);
  static const packetsSlow = Duration(milliseconds: 7500);

  /// §4.1 every third edge starts this far into its loop.
  static const packetsLate = Duration(milliseconds: 2400);

  /// §4.2 one there-and-back of a star.
  static const stars = Duration(milliseconds: 3600);

  /// §4.3 the spine of the mark, drawn once.
  static const spine = Duration(milliseconds: 1600);

  /// §4.3 one breath of a circle of the mark.
  static const breathe = Duration(milliseconds: 3200);

  /// §4.4 one crawl of the loader.
  static const crawl = Duration(milliseconds: 1100);

  /// §4.5 one sweep of the bar.
  static const bar = Duration(milliseconds: 1400);

  /// §4.6 the rise of a block, and the step between two blocks.
  static const rise = Duration(milliseconds: 600);
  static const riseStep = Duration(milliseconds: 80);
  static const riseCurve = Cubic(0.2, 0.7, 0.2, 1);

  /// §4.7 the shake of the password on a wrong password.
  static const shake = Duration(milliseconds: 450);

  /// §4.8 one turn of the spinner.
  static const spin = Duration(milliseconds: 900);

  /// §5 the form fading out before the welcome.
  static const fadeOut = Duration(milliseconds: 200);
}

/// The system asks for less motion: every loop stops at its rest frame.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Where a loop of [period] is, `0 ≤ phase < 1`, [delay] after it started,
/// given that its controller is at [value] of one period. A positive [delay]
/// is a later start; a negative one, a start that far in.
double loopPhase(double value, Duration period, [Duration delay = .zero]) {
  final x = value - delay.inMicroseconds / period.inMicroseconds;
  return x - x.floorToDouble();
}

/// The value of a CSS keyframe track at [phase] (0–1): [frames] are
/// `(offset, value)` pairs from 0 to 1, each segment eased by [curve].
double keyframes(
  double phase,
  List<(double, double)> frames, [
  Curve curve = Curves.easeInOut,
]) {
  for (var i = 1; i < frames.length; i++) {
    final (a, va) = frames[i - 1];
    final (b, vb) = frames[i];
    if (phase <= b) {
      final t = b == a ? 1.0 : ((phase - a) / (b - a)).clamp(0.0, 1.0);
      return va + (vb - va) * curve.transform(t);
    }
  }
  return frames.last.$2;
}
