import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onTick] every [period] while it is in the tree and [enabled].
///
/// The clock of a screen that reads again by itself (the Log tab's `every
/// 5 s`). The timer stops when [enabled] turns false and when the widget
/// leaves the tree; what a tick does is the caller's.
class Every extends StatefulWidget {
  const Every({
    required this.period,
    required this.onTick,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Duration period;
  final VoidCallback onTick;
  final bool enabled;
  final Widget child;

  @override
  State<Every> createState() => _EveryState();
}

class _EveryState extends State<Every> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Every old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled || old.period != widget.period) {
      _timer?.cancel();
      _timer = null;
      _sync();
    }
  }

  void _sync() {
    if (widget.enabled) {
      _timer ??= Timer.periodic(widget.period, (_) => widget.onTick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
