import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// The indefinite bar of the log-in board (docs/design/specs/login.md §4.5):
/// a strip 40 % of the track wide sweeps from −100 % to +250 % of its own
/// width every 1.4 s, `ease-in-out`, clipped by the track. Along the bottom of
/// the busy Log in button it is a plain strip; on the welcome it sits in a
/// track and fades in and out at its ends. Under reduced motion it is hidden.
class SweepBar extends StatefulWidget {
  /// The strip alone, in [color] (the button's bar): the parent clips it.
  const SweepBar.strip({
    required Color this.color,
    this.height = 3,
    super.key,
  }) : track = null,
       width = null,
       radius = 0;

  /// The welcome's bar: a [track] [width] × [height] with a strip fading
  /// transparent → [color] → transparent.
  const SweepBar.track({
    required Color this.color,
    required Color this.track,
    this.width = 260,
    this.height = 4,
    super.key,
  }) : radius = 2;

  final Color? color;
  final Color? track;
  final double? width;
  final double height;
  final double radius;

  @override
  State<SweepBar> createState() => _SweepBarState();
}

class _SweepBarState extends State<SweepBar>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: Motion.bar);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat().ignore();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final radius = BorderRadius.circular(widget.radius);
    final faded = widget.track != null;
    final strip = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: faded ? null : widget.color,
        gradient: faded
            ? LinearGradient(
                colors: [
                  widget.color!.withValues(alpha: 0),
                  widget.color!,
                  widget.color!.withValues(alpha: 0),
                ],
              )
            : null,
      ),
    );
    final bar = LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth * .4;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, child) {
              final e = Curves.easeInOut.transform(_sweep.value);
              return Stack(
                children: [
                  Positioned(
                    left: w * (-1 + 3.5 * e),
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: child!,
                  ),
                ],
              );
            },
            child: strip,
          ),
        );
      },
    );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.track, borderRadius: radius),
        child: still ? null : ClipRRect(borderRadius: radius, child: bar),
      ),
    );
  }
}
