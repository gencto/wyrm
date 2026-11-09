import 'package:flutter/material.dart';

import '../indicators/sweep_bar.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';

/// A workspace's content while it reads again data it already shows
/// (docs/studio.md §6.7, stale while revalidate): the content stays as it
/// is, a thin ember strip sweeps along the top edge, and a `PageHeader`
/// inside says [label] (`Updating…`) beside its subtitle.
///
/// The strip lies over the content, so nothing moves when it comes and
/// goes. Under reduced motion it stands still at 60 % — a refresh must stay
/// visible even when nothing may move. A first load, with nothing to keep
/// on screen, is not this widget's: the workspace shows its own empty or
/// loading state.
class RefreshFrame extends StatelessWidget {
  const RefreshFrame({
    required this.child,
    this.refreshing = false,
    this.label,
    super.key,
  });

  final Widget child;

  /// A read is running and there is content to keep.
  final bool refreshing;

  /// `Updating…`, resolved: the status a `PageHeader` shows and what
  /// assistive technology reads.
  final String? label;

  /// The strip's height.
  static const height = 2.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        Positioned.fill(
          child: RefreshScope(
            status: refreshing ? label : null,
            child: child,
          ),
        ),
        if (refreshing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Semantics(
                label: label,
                liveRegion: true,
                child: reduceMotion(context)
                    ? Container(
                        height: height,
                        color: c.ember.withValues(alpha: .6),
                      )
                    : SweepBar.strip(color: c.ember, height: height),
              ),
            ),
          ),
      ],
    );
  }
}

/// What a [RefreshFrame] tells the status lines inside it: the text to show
/// while it refreshes, null otherwise. Read with [RefreshScope.statusOf],
/// like a [DefaultTextStyle]: it is the frame's own data, not the app's
/// state.
class RefreshScope extends InheritedWidget {
  const RefreshScope({required this.status, required super.child, super.key});

  final String? status;

  /// The status of the nearest [RefreshFrame], or null.
  static String? statusOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RefreshScope>()?.status;

  @override
  bool updateShouldNotify(RefreshScope old) => old.status != status;
}
