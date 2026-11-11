import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// A window that floats over the page without blocking it (not a modal):
/// the [header] row is its handle to move it, the corner at the bottom
/// right resizes it, and the close button or Esc calls [onClose] (Esc
/// calls [onEscape] instead while that is given: an editor inside takes
/// the first Esc). It keeps
/// its place and size while its content changes, so a live value can be
/// redrawn in it.
///
/// It fills the layer it is put in (a `Positioned.fill` of the page's
/// `Stack`); outside the window, taps reach the page below.
class FloatingWindow extends StatefulWidget {
  const FloatingWindow({
    required this.header,
    required this.child,
    required this.onClose,
    this.onEscape,
    this.closeLabel = 'Close',
    this.initialSize = const Size(440, 380),
    this.minSize = const Size(280, 180),
    super.key,
  });

  /// The title row (it is the handle to move the window).
  final Widget header;
  final Widget child;
  final VoidCallback onClose;

  /// What Esc does instead of closing; null: Esc closes.
  final VoidCallback? onEscape;
  final String closeLabel;
  final Size initialSize;
  final Size minSize;

  @override
  State<FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<FloatingWindow> {
  Offset? _at;
  late Size _size = widget.initialSize;
  final _focus = FocusNode(debugLabel: 'FloatingWindow');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final area = box.biggest;
        final w = _size.width.clamp(widget.minSize.width, area.width);
        final h = _size.height.clamp(widget.minSize.height, area.height);
        // At first: near the top right, over the inspector's left edge.
        final at = _clamp(
          _at ?? Offset(area.width - w - 360, 72),
          area,
          Size(w, h),
        );
        return Stack(
          children: [
            Positioned(
              left: at.dx,
              top: at.dy,
              width: w,
              height: h,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onEscape ?? widget.onClose,
                },
                child: Focus(
                  focusNode: _focus,
                  child: Listener(
                    // A click anywhere in the window gives it the keys (Esc),
                    // unless what was clicked inside took them (a grid, a
                    // field): checked after the click's own focus moves.
                    onPointerDown: (_) => scheduleMicrotask(() {
                      if (mounted && !_focus.hasFocus) {
                        _focus.requestFocus();
                      }
                    }),
                    child: Material(
                      color: c.ground2,
                      elevation: 12,
                      shadowColor: c.ground0.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: Radii.card,
                        side: BorderSide(color: c.line2),
                      ),
                      clipBehavior: .antiAlias,
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: .stretch,
                            children: [
                              GestureDetector(
                                behavior: .opaque,
                                onPanUpdate: (d) => setState(
                                  () => _at = _clamp(
                                    at + d.delta,
                                    area,
                                    Size(w, h),
                                  ),
                                ),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.move,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      8,
                                      6,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.ground3,
                                      border: Border(
                                        bottom: BorderSide(color: c.line1),
                                      ),
                                    ),
                                    child: Row(
                                      spacing: 8,
                                      children: [
                                        Expanded(child: widget.header),
                                        IconButton(
                                          tooltip: widget.closeLabel,
                                          visualDensity: .compact,
                                          onPressed: widget.onClose,
                                          icon: AppIcon(
                                            'ui_close',
                                            size: 16,
                                            color: c.text3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(child: widget.child),
                            ],
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            width: 18,
                            height: 18,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeDownRight,
                              child: GestureDetector(
                                behavior: .opaque,
                                onPanUpdate: (d) => setState(
                                  () => _size = Size(
                                    (w + d.delta.dx).clamp(
                                      widget.minSize.width,
                                      area.width - at.dx,
                                    ),
                                    (h + d.delta.dy).clamp(
                                      widget.minSize.height,
                                      area.height - at.dy,
                                    ),
                                  ),
                                ),
                                child: CustomPaint(
                                  painter: _Grip(c.text4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Offset _clamp(Offset at, Size area, Size window) => Offset(
    at.dx.clamp(0, (area.width - window.width).clamp(0, double.infinity)),
    at.dy.clamp(0, (area.height - window.height).clamp(0, double.infinity)),
  );
}

/// Two short diagonal strokes in the corner that resizes.
class _Grip extends CustomPainter {
  const _Grip(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = .round;
    final r = size.width - 4;
    final b = size.height - 4;
    canvas
      ..drawLine(Offset(r, b - 8), Offset(r - 8, b), p)
      ..drawLine(Offset(r, b - 4), Offset(r - 4, b), p);
  }

  @override
  bool shouldRepaint(_Grip old) => old.color != color;
}
