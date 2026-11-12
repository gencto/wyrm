import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';

/// Which side panel of a [SidePanels] changed.
enum PanelSide { left, right }

/// The widths a viewer gave the side panels of one workspace; null means
/// the panel's default. What a page takes from its connector.
final class SidePanelWidths extends Equatable {
  const SidePanelWidths({this.left, this.right});

  final double? left;
  final double? right;

  @override
  List<Object?> get props => [left, right];
}

/// One side panel of a [SidePanels]: what it draws and its bounds.
///
/// [width] is the stored width (null: [defaultWidth]); the panel clamps it to
/// [minWidth]…[maxWidth], which default to 200–520 on the left and 280–640 on
/// the right.
final class SidePanel {
  const SidePanel({
    required this.child,
    required this.defaultWidth,
    this.width,
    this.minWidth,
    this.maxWidth,
  });

  final Widget child;
  final double defaultWidth;
  final double? width;
  final double? minWidth;
  final double? maxWidth;
}

/// A workspace with an optional panel on each side of a [center]: the tree
/// or palette on the left, the inspector on the right.
///
/// A drag handle sits on the inner edge of each panel: an 8 px hit area
/// centred on the panel's own 1 px `line1` border, which is the line at rest;
/// on hover, drag or focus the handle draws that line in `ember` over it. The
/// cursor is the resize-column one. The handle takes no layout width, and at
/// rest it paints nothing, so a panel looks as it did without it.
///
/// Dragging moves the edge; a double click puts the panel back to its
/// default width; with the handle focused, ← and → move the edge by 16 px
/// (on the right panel ← widens it).
///
/// The center never gets less than [minCenter]: when the window is too
/// narrow, both panels shrink in proportion to their room above their
/// minimum, down to it. Only when the two minimums and [minCenter] do not fit
/// does the center go below [minCenter].
///
/// The widget is data-driven: it draws [left] and [right] at the widths it is
/// handed and reports a new width through [onChanged] — at the end of a drag,
/// on a double click and on each key step. It shows the width it reported
/// until the next one arrives; it never stores one.
class SidePanels extends StatefulWidget {
  const SidePanels({
    required this.center,
    this.left,
    this.right,
    this.onChanged,
    this.minCenter = 480,
    super.key,
  });

  /// Bounds of a left panel that names none.
  static const leftMin = 200.0;
  static const leftMax = 520.0;

  /// Bounds of a right panel that names none.
  static const rightMin = 280.0;
  static const rightMax = 640.0;

  /// What one arrow key moves an edge by.
  static const keyStep = 16.0;

  final SidePanel? left;
  final Widget center;
  final SidePanel? right;
  final void Function(PanelSide side, double width)? onChanged;
  final double minCenter;

  @override
  State<SidePanels> createState() => _SidePanelsState();
}

class _SidePanelsState extends State<SidePanels> {
  /// The width reported last, shown until the next one comes in.
  final _local = <PanelSide, double>{};

  /// Widths on screen at the last layout, after the shrink.
  final _shown = <PanelSide, double>{};
  double _total = 0;

  final Map<PanelSide, FocusNode> _focus = {
    PanelSide.left: FocusNode(debugLabel: 'left panel edge'),
    PanelSide.right: FocusNode(debugLabel: 'right panel edge'),
  };

  PanelSide? _dragging;
  double _dragStartX = 0;
  double _dragStartWidth = 0;

  @override
  void didUpdateWidget(SidePanels old) {
    super.didUpdateWidget(old);
    if (old.left?.width != widget.left?.width) {
      _local.remove(PanelSide.left);
    }
    if (old.right?.width != widget.right?.width) {
      _local.remove(PanelSide.right);
    }
  }

  @override
  void dispose() {
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  SidePanel? _panel(PanelSide side) =>
      side == .left ? widget.left : widget.right;

  double _min(PanelSide side) =>
      _panel(side)?.minWidth ??
      (side == .left ? SidePanels.leftMin : SidePanels.rightMin);

  double _max(PanelSide side) => math.max(
    _min(side),
    _panel(side)?.maxWidth ??
        (side == .left ? SidePanels.leftMax : SidePanels.rightMax),
  );

  /// The width a panel asks for, within its bounds.
  double _wanted(PanelSide side) {
    final p = _panel(side)!;
    final w = _local[side] ?? p.width ?? p.defaultWidth;
    return (w.isFinite ? w : p.defaultWidth).clamp(_min(side), _max(side));
  }

  /// The widest [side] may be now: its max, and room for the center.
  double _limit(PanelSide side) {
    final other = side == .left ? PanelSide.right : PanelSide.left;
    final room = _total - widget.minCenter - (_shown[other] ?? 0);
    return math.max(_min(side), math.min(_max(side), room));
  }

  void _report(PanelSide side, double width) {
    // Two key steps may land before the next layout.
    _shown[side] = width;
    setState(() => _local[side] = width);
    widget.onChanged?.call(side, width);
  }

  void _onDragStart(PanelSide side, DragStartDetails d) {
    setState(() {
      _dragging = side;
      _dragStartX = d.globalPosition.dx;
      _dragStartWidth = _shown[side] ?? _wanted(side);
    });
  }

  void _onDragUpdate(PanelSide side, DragUpdateDetails d) {
    final dx = d.globalPosition.dx - _dragStartX;
    final w = _dragStartWidth + (side == .left ? dx : -dx);
    setState(() => _local[side] = w.clamp(_min(side), _limit(side)));
  }

  void _onDragEnd(PanelSide side) {
    final w = _local[side];
    setState(() => _dragging = null);
    if (w != null) {
      widget.onChanged?.call(side, w);
    }
  }

  KeyEventResult _onKey(PanelSide side, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return .ignored;
    }
    final double sign;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      sign = -1;
    } else if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      sign = 1;
    } else {
      return .ignored;
    }
    // An arrow moves the edge: on the right panel, ← widens it.
    final step = SidePanels.keyStep * (side == .left ? sign : -sign);
    final now = _shown[side] ?? _wanted(side);
    _report(side, (now + step).clamp(_min(side), _limit(side)));
    return .handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _total = box.maxWidth;
      var l = widget.left == null ? 0.0 : _wanted(.left);
      var r = widget.right == null ? 0.0 : _wanted(.right);
      final excess = l + r + widget.minCenter - _total;
      if (excess > 0) {
        final slackL = widget.left == null ? 0.0 : l - _min(.left);
        final slackR = widget.right == null ? 0.0 : r - _min(.right);
        final slack = slackL + slackR;
        if (slack > 0) {
          final cut = math.min(excess, slack);
          l -= cut * slackL / slack;
          r -= cut * slackR / slack;
        }
      }
      _shown
        ..clear()
        ..addAll({
          if (widget.left != null) PanelSide.left: l,
          if (widget.right != null) PanelSide.right: r,
        });
      return Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                if (widget.left case final p?)
                  SizedBox(width: l, child: p.child),
                Expanded(child: widget.center),
                if (widget.right case final p?)
                  SizedBox(width: r, child: p.child),
              ],
            ),
          ),
          // The line sits on the panel's own border pixel: the last column
          // of the left panel, the first column of the right one.
          if (widget.left != null)
            Positioned(
              left: l - 4,
              top: 0,
              bottom: 0,
              width: 8,
              child: _handle(.left, lineAt: 3),
            ),
          if (widget.right != null)
            Positioned(
              left: _total - r - 4,
              top: 0,
              bottom: 0,
              width: 8,
              child: _handle(.right, lineAt: 4),
            ),
        ],
      );
    },
  );

  Widget _handle(PanelSide side, {required double lineAt}) => _Handle(
    key: ValueKey(side),
    focusNode: _focus[side]!,
    dragging: _dragging == side,
    lineAt: lineAt,
    onKey: (e) => _onKey(side, e),
    onDragStart: (d) => _onDragStart(side, d),
    onDragUpdate: (d) => _onDragUpdate(side, d),
    onDragEnd: () => _onDragEnd(side),
    // A pointer never takes focus: the handle would stay lit and pull it
    // away from a field the user is typing in. Tab reaches it.
    onReset: () =>
        _report(side, _panel(side)!.defaultWidth.clamp(_min(side), _max(side))),
  );
}

/// The drag handle on one panel edge.
class _Handle extends StatefulWidget {
  const _Handle({
    required this.focusNode,
    required this.dragging,
    required this.lineAt,
    required this.onKey,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    super.key,
  });

  final FocusNode focusNode;
  final bool dragging;
  final double lineAt;
  final KeyEventResult Function(KeyEvent) onKey;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  var _hover = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = _hover || _focused || widget.dragging;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, e) => widget.onKey(e),
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: .opaque,
          dragStartBehavior: .down,
          onHorizontalDragStart: widget.onDragStart,
          onHorizontalDragUpdate: widget.onDragUpdate,
          onHorizontalDragEnd: (_) => widget.onDragEnd(),
          onHorizontalDragCancel: widget.onDragEnd,
          onDoubleTap: widget.onReset,
          child: Stack(
            children: [
              if (lit)
                Positioned(
                  left: widget.lineAt,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: c.ember),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
