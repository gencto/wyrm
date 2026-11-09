import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// What a frameless desktop window asks of a page's top area (owner
/// decision 2026-11-09, docs/studio.md §7.1). The app decides it from the
/// platform and the window's state; a page only draws it. The default is a
/// window with a frame of its own (web, mobile, tests): no room kept and
/// nothing to drag.
final class WindowBarVm extends Equatable {
  const WindowBarVm({
    this.leading = 0,
    this.trailing = 0,
    this.onDrag,
    this.onZoom,
  });

  /// Room kept at the left for the native window buttons (macOS: 92; 0 in
  /// full screen).
  final double leading;

  /// Room kept at the right for the `WindowControls` the app draws over
  /// the corner (Windows, Linux).
  final double trailing;

  /// A drag that starts on the bar moves the window; null: the bar is not
  /// a drag area.
  final VoidCallback? onDrag;

  /// A double click on the bar's empty space (maximize or restore, as a
  /// native title bar).
  final VoidCallback? onZoom;

  @override
  List<Object?> get props => [leading, trailing, onDrag != null];
}

/// The top area of a page as the window's title bar: it keeps the room
/// [WindowBarVm] asks for at both ends and makes the bar the drag area of
/// the window. The controls inside stay clickable: a click is theirs, a
/// drag that starts on them moves the window, and a double click counts
/// only on the empty space between them.
class WindowBar extends StatelessWidget {
  const WindowBar({
    required this.child,
    this.vm = const WindowBarVm(),
    this.padding = 0,
    super.key,
  });

  final WindowBarVm vm;
  final Widget child;

  /// The bar's own horizontal padding; the room for the window buttons
  /// replaces it at their end, it is not added to it.
  final double padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.only(
        left: math.max(padding, vm.leading),
        right: math.max(padding, vm.trailing),
      ),
      child: child,
    );
    if (vm.onDrag == null) {
      return content;
    }
    return GestureDetector(
      behavior: .translucent,
      onPanStart: (_) => vm.onDrag!(),
      child: Stack(
        fit: .passthrough,
        children: [
          // Under the content, so a control never waits for a second tap.
          Positioned.fill(
            child: GestureDetector(
              behavior: .opaque,
              onDoubleTap: vm.onZoom,
            ),
          ),
          content,
        ],
      ),
    );
  }
}
