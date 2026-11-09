import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Lets its child rise into place once, when it is first shown
/// (docs/design/specs/login.md §4.6): opacity 0 → 1 and 14 px up to 0 over
/// 0.6 s on `cubic-bezier(0.2, 0.7, 0.2, 1)`, after [order] × 80 ms (the
/// board's classes `d1`…`d4`). Hidden until its turn, like the board's
/// `animation-fill-mode: both`. Under reduced motion it is in place at once.
class Rise extends StatefulWidget {
  const Rise({required this.child, this.order = 0, super.key});

  final Widget child;

  /// The block's place in the stagger: 0 starts at once, 1 after 80 ms, …
  final int order;

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final Duration _delay = Motion.riseStep * widget.order;
  late final _rise = AnimationController(
    vsync: this,
    duration: Motion.rise + _delay,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _rise,
    curve: Interval(
      _delay.inMicroseconds / _rise.duration!.inMicroseconds,
      1,
      curve: Motion.riseCurve,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _rise
        ..stop()
        ..value = 1;
    } else if (_rise.isDismissed) {
      _rise.forward().ignore();
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - _t.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
