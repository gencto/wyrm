import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../indicators/wyrm_mark.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import 'rise.dart';

/// How much of the hero there is room for (docs/design/specs/login.md §1).
enum LoginHeroSize {
  /// Beside the form: everything, headline 40.
  wide,

  /// Above the form, 420 high (below 1080 px): everything, headline 28.
  stacked,

  /// Above the form, 220 high (below 700 px): the logo and the mark only.
  small,
}

/// The left side of the log-in page (docs/design/specs/login.md §2): the
/// logo, the large mark, the headline (its second line ember), the lead and
/// the legend, top to bottom with the space between them, over the living
/// network (§4.1, §4.2). Padding 40 × 48, a radial glow, a `ground3` line on
/// the right.
class LoginHero extends StatelessWidget {
  const LoginHero({this.size = LoginHeroSize.wide, super.key});

  final LoginHeroSize size;

  /// The glow's warm centre (the board's `#1A1511`).
  static const glow = Color(0xFF1A1511);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = size == LoginHeroSize.small;
    final headline = size == LoginHeroSize.wide ? 40.0 : 28.0;
    final h1 = TextStyle(
      fontSize: headline,
      height: 1.12,
      leadingDistribution: .even,
      fontWeight: .w600,
      letterSpacing: -.02 * headline,
      color: c.text1,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.ground3)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 1),
        child: ClipRect(
          child: CustomPaint(
            painter: _Glow(glow, c.ground0),
            child: Stack(
              fit: .expand,
              children: [
                const Positioned.fill(child: _NetworkLayer()),
                Padding(
                  // 220 high below 700 px: 24 around the logo and the mark.
                  padding: small
                      ? const EdgeInsets.all(24)
                      : const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 40,
                        ),
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisAlignment: .spaceBetween,
                    children: [
                      const Rise(child: WyrmLogo(large: true)),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: .start,
                          spacing: 22,
                          children: [
                            const WyrmMark(),
                            if (!small) ...[
                              Rise(
                                order: 1,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: S.current.heroHeadline1),
                                      const TextSpan(text: '\n'),
                                      TextSpan(
                                        text: S.current.heroHeadline2,
                                        style: TextStyle(color: c.emberSoft),
                                      ),
                                    ],
                                  ),
                                  style: h1,
                                ),
                              ),
                              Rise(
                                order: 2,
                                child: Text(
                                  S.current.heroLead,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.6,
                                    leadingDistribution: .even,
                                    color: c.text3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!small)
                        Rise(
                          order: 3,
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 8,
                            crossAxisAlignment: .center,
                            children: [
                              _legend(c.good, S.current.legendValues, c),
                              _legend(c.ember, S.current.legendCommands, c),
                              Text(
                                S.current.legendNote,
                                style: TextStyle(fontSize: 12, color: c.text4),
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(Color line, String label, AppColors c) => Row(
    mainAxisSize: .min,
    spacing: 6,
    children: [
      SizedBox(width: 14, height: 2, child: ColoredBox(color: line)),
      Text(label, style: TextStyle(fontSize: 12, color: c.text4)),
    ],
  );
}

/// `radial-gradient(120% 90% at 20% 30%, #1A1511 0%, #0E1113 60%)`: an
/// ellipse 1.2 × the width by 0.9 × the height, centred at 20 % / 30 %.
class _Glow extends CustomPainter {
  _Glow(this.centre, this.ground);

  final Color centre;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width * .2, size.height * .3);
    final rx = size.width * 1.2;
    final ry = size.height * .9;
    // A circle of radius rx, squeezed to ry vertically about the centre.
    final m = Matrix4.identity()
      ..translateByDouble(o.dx, o.dy, 0, 1)
      ..scaleByDouble(1, ry / rx, 1, 1)
      ..translateByDouble(-o.dx, -o.dy, 0, 1);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          o,
          rx,
          [centre, ground],
          [0, .6],
          .clamp,
          m.storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_Glow old) => old.centre != centre || old.ground != ground;
}

/// The network behind the hero, its own loops (§4.1, §4.2).
class _NetworkLayer extends StatefulWidget {
  const _NetworkLayer();

  @override
  State<_NetworkLayer> createState() => _NetworkLayerState();
}

class _NetworkLayerState extends State<_NetworkLayer>
    with TickerProviderStateMixin {
  late final _fast = AnimationController(vsync: this, duration: Motion.packets);
  late final _slow = AnimationController(
    vsync: this,
    duration: Motion.packetsSlow,
  );
  late final _stars = AnimationController(vsync: this, duration: Motion.stars);

  List<AnimationController> get _loops => [_fast, _slow, _stars];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final loop in _loops) {
      if (reduceMotion(context)) {
        loop.stop();
      } else if (!loop.isAnimating) {
        unawaited(loop.repeat());
      }
    }
  }

  @override
  void dispose() {
    for (final loop in _loops) {
      loop.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _Network(
          fast: _fast,
          slow: _slow,
          stars: _stars,
          still: reduceMotion(context),
          teal: c.good,
          ember: c.ember,
          grey: c.line3,
          star: c.line1,
          node: c.ground1,
        ),
      ),
    );
  }
}

/// The board's network in its 900 × 900 space, scaled to cover the hero
/// (`xMidYMid slice`, like `BoxFit.cover`).
///
/// - 34 stars from the LCG `seed = (seed·9301 + 49297) mod 233280`, seed 7:
///   x, y rounded, r to 0.1, delay to 0.01 s; opacity 0.25 ↔ 0.9 every 3.6 s,
///   `ease-in-out` per half.
/// - Eleven edges, each `M a Q (mid x, mid y − 40) b`, `#2A2F33` 1.2; on each
///   a packet of 3 every 160 along the path moving 160 per loop (4.8 s, odd
///   edges 7.5 s, every third edge 2.4 s in), width 2.4, round caps, teal or
///   (every fourth edge) ember.
/// - Nine nodes: a ring r 8 (the hub r 11) stroke 1.6 on `ground1` and a
///   core r 3 (4) at 0.9.
///
/// Under reduced motion the packets are hidden and the stars at 0.5.
class _Network extends CustomPainter {
  _Network({
    required this.fast,
    required this.slow,
    required this.stars,
    required this.still,
    required this.teal,
    required this.ember,
    required this.grey,
    required this.star,
    required this.node,
  }) : super(repaint: Listenable.merge([fast, slow, stars]));

  final Animation<double> fast;
  final Animation<double> slow;
  final Animation<double> stars;
  final bool still;
  final Color teal;
  final Color ember;
  final Color grey;
  final Color star;
  final Color node;

  static const _edgeInk = Color(0xFF2A2F33);

  static const _nodes = [
    Offset(150, 640),
    Offset(300, 560),
    Offset(470, 610),
    Offset(620, 520),
    Offset(770, 600),
    Offset(380, 740),
    Offset(560, 760),
    Offset(700, 720),
    Offset(240, 780),
  ];

  static const _edges = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (1, 5),
    (5, 6),
    (6, 7),
    (2, 6),
    (0, 8),
    (8, 5),
    (4, 7),
  ];

  static final List<Path> _paths = [
    for (final (a, b) in _edges)
      Path()
        ..moveTo(_nodes[a].dx, _nodes[a].dy)
        ..quadraticBezierTo(
          (_nodes[a].dx + _nodes[b].dx) / 2,
          (_nodes[a].dy + _nodes[b].dy) / 2 - 40,
          _nodes[b].dx,
          _nodes[b].dy,
        ),
  ];

  static final List<ui.PathMetric> _metrics = [
    for (final p in _paths) p.computeMetrics().first,
  ];

  /// `(x, y, r, delay in s)` of the 34 stars, as the board seeds them.
  static final List<(double, double, double, double)> _stars = () {
    var seed = 7;
    double rnd() {
      seed = (seed * 9301 + 49297) % 233280;
      return seed / 233280;
    }

    double fixed(double v, int digits) =>
        double.parse(v.toStringAsFixed(digits));
    return [
      for (var i = 0; i < 34; i++)
        (
          (rnd() * 900).roundToDouble(),
          (rnd() * 900).roundToDouble(),
          fixed(.8 + rnd() * 1.4, 1),
          fixed(rnd() * 3.6, 2),
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.max(size.width / 900, size.height / 900);
    canvas
      ..save()
      ..translate((size.width - 900 * k) / 2, (size.height - 900 * k) / 2)
      ..scale(k);

    for (final (x, y, r, d) in _stars) {
      final opacity = still
          ? .5
          : keyframes(
              loopPhase(
                stars.value,
                Motion.stars,
                Duration(microseconds: (d * 1e6).round()),
              ),
              const [(0, .25), (.5, .9), (1, .25)],
            );
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = star.withValues(alpha: star.a * opacity),
      );
    }

    final edge = Paint()
      ..color = _edgeInk
      ..style = .stroke
      ..strokeWidth = 1.2;
    for (final p in _paths) {
      canvas.drawPath(p, edge);
    }

    if (!still) {
      for (final (i, metric) in _metrics.indexed) {
        final slowEdge = i.isOdd;
        final phase = loopPhase(
          (slowEdge ? slow : fast).value,
          slowEdge ? Motion.packetsSlow : Motion.packets,
          i % 3 == 0 ? -Motion.packetsLate : Duration.zero,
        );
        final packet = Paint()
          ..color = i % 4 == 3 ? ember : teal
          ..style = .stroke
          ..strokeWidth = 2.4
          ..strokeCap = .round;
        for (var s = phase * 160 - 160; s < metric.length; s += 160) {
          final from = math.max(0, s).toDouble();
          final to = math.min(metric.length, s + 3);
          if (to > from) {
            canvas.drawPath(metric.extractPath(from, to), packet);
          }
        }
      }
    }

    for (final (i, o) in _nodes.indexed) {
      final hub = i == 2;
      final ink = hub ? ember : (i % 3 == 0 ? grey : teal);
      canvas
        ..drawCircle(o, hub ? 11 : 8, Paint()..color = node)
        ..drawCircle(
          o,
          hub ? 11 : 8,
          Paint()
            ..color = ink
            ..style = .stroke
            ..strokeWidth = 1.6,
        )
        ..drawCircle(
          o,
          hub ? 4 : 3,
          Paint()..color = ink.withValues(alpha: .9),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Network old) =>
      old.still != still ||
      old.teal != teal ||
      old.ember != ember ||
      old.grey != grey ||
      old.star != star ||
      old.node != node;
}
