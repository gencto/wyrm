import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/motion.dart';

/// The two loaders of the log-in board (docs/design/specs/login.md §4.4).
enum WyrmLoaderSize {
  /// In a button: dots 6, 7, 8, 7, 6 apart by 5, filled in the button's ink.
  small(sizes: [6, 7, 8, 7, 6], gap: 5, height: 18),

  /// On the welcome: rings 14, 17, 20, 17, 14 apart by 10, 3 px ember, the
  /// middle one filled.
  large(sizes: [14, 17, 20, 17, 14], gap: 10, height: 48);

  const WyrmLoaderSize({
    required this.sizes,
    required this.gap,
    required this.height,
  });

  final List<double> sizes;
  final double gap;
  final double height;
}

/// The crawl loader: five beads of the WYRM mark in a row, bottom-aligned,
/// each rising, swelling and brightening in turn (§4.4).
///
/// Keyframes of `wy-crawl`, 1.1 s, `ease-in-out` per segment, repeating:
/// 0 %: y 0, scale 1, opacity 0.4 · 35 %: y −6, scale 1.28, opacity 1 ·
/// 70 %: y 0, scale 1, opacity 0.7 · 100 % = 0 %; bead `i` starts 0.11·i s
/// later. One controller for the five. Under reduced motion the beads stand
/// still at full opacity.
class WyrmLoader extends StatefulWidget {
  const WyrmLoader({
    this.size = WyrmLoaderSize.small,
    this.color,
    this.label,
    super.key,
  });

  final WyrmLoaderSize size;

  /// What is loading, for a screen reader (`Opening the tree`); null for a
  /// loader beside a label that already says it.
  final String? label;

  /// The beads' colour: the button's ink for [WyrmLoaderSize.small], ember
  /// for [WyrmLoaderSize.large] when null.
  final Color? color;

  @override
  State<WyrmLoader> createState() => _WyrmLoaderState();
}

class _WyrmLoaderState extends State<WyrmLoader>
    with SingleTickerProviderStateMixin {
  late final _crawl = AnimationController(vsync: this, duration: Motion.crawl);

  static const _step = Duration(milliseconds: 110);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _crawl.stop();
    } else if (!_crawl.isAnimating) {
      unawaited(_crawl.repeat());
    }
  }

  @override
  void dispose() {
    _crawl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = widget.size;
    final large = size == WyrmLoaderSize.large;
    final color = widget.color ?? (large ? c.ember : c.onEmber);
    final still = reduceMotion(context);
    return Semantics(
      label: widget.label,
      excludeSemantics: true,
      child: SizedBox(
        height: size.height,
        child: AnimatedBuilder(
          animation: _crawl,
          builder: (context, _) => Row(
            mainAxisSize: .min,
            crossAxisAlignment: .end,
            spacing: size.gap,
            children: [
              for (final (i, d) in size.sizes.indexed)
                _bead(
                  d: d,
                  color: color,
                  ring: large && i != 2,
                  phase: still
                      ? null
                      : loopPhase(_crawl.value, Motion.crawl, _step * i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bead({
    required double d,
    required Color color,
    required bool ring,
    required double? phase,
  }) {
    final y = phase == null
        ? 0.0
        : keyframes(phase, const [(0, 0), (.35, -6), (.7, 0), (1, 0)]);
    final scale = phase == null
        ? 1.0
        : keyframes(phase, const [(0, 1), (.35, 1.28), (.7, 1), (1, 1)]);
    final opacity = phase == null
        ? 1.0
        : keyframes(phase, const [(0, .4), (.35, 1), (.7, .7), (1, .4)]);
    return Transform.translate(
      offset: Offset(0, y),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: .circle,
              color: ring ? null : color,
              border: ring ? .all(color: color, width: 3) : null,
            ),
          ),
        ),
      ),
    );
  }
}
