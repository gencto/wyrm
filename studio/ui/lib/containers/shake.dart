import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Shakes its child sideways once each time [trigger] changes to a new
/// non-null value (docs/design/specs/login.md §4.7, a wrong password):
/// 0.45 s through the board's `wy-shake` keyframes, x 0 → −1 (10 %) → 2 →
/// −4 → 4 → −4 → 4 → −4 → 2 → −1 (90 %) → 0. The board names no timing
/// function, so each segment eases with CSS `ease`. Under reduced motion it
/// stays still.
class Shake extends StatefulWidget {
  const Shake({required this.child, this.trigger, super.key});

  final Widget child;

  /// A new value shakes; null and the same value do not.
  final Object? trigger;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: Motion.shake);

  static const _frames = [
    (0.0, 0.0),
    (.1, -1.0),
    (.2, 2.0),
    (.3, -4.0),
    (.4, 4.0),
    (.5, -4.0),
    (.6, 4.0),
    (.7, -4.0),
    (.8, 2.0),
    (.9, -1.0),
    (1.0, 0.0),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.trigger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null && widget.trigger != old.trigger) {
      _start();
    }
  }

  void _start() {
    if (mounted && !reduceMotion(context)) {
      _shake.forward(from: 0).ignore();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shake,
    builder: (context, child) => Transform.translate(
      offset: Offset(
        _shake.isAnimating ? keyframes(_shake.value, _frames, Curves.ease) : 0,
        0,
      ),
      child: child,
    ),
    child: widget.child,
  );
}
