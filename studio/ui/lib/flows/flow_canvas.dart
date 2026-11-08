import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import 'flow_block_view.dart';
import 'flow_legend.dart';

/// One wire: output `<from>.<fromPort>` → input `<to>.<toPort>`.
final class FlowWireVm extends Equatable {
  const FlowWireVm(
    this.from,
    this.fromPort,
    this.to,
    this.toPort, {
    this.writes = false,
    this.warning,
    this.warningNote = '',
  });

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  /// It writes to a device (into a writable point, a `set` or an `invoke`):
  /// ember; everything else reads a value: teal.
  final bool writes;

  /// A chip on the wire (`fires at deploy`: a parameter's echo into a
  /// device sends at start, ADR 0038 §6), with [warningNote] as its tooltip.
  final String? warning;
  final String warningNote;

  @override
  List<Object?> get props => [
    from,
    fromPort,
    to,
    toPort,
    writes,
    warning,
    warningNote,
  ];
}

/// The canvas of the flow editor (spec §3–§5): blocks on a dot grid, S-curve
/// wires from a field's right port to another's left port, the legend
/// pinned bottom-left. A palette entry dropped on the canvas places a block
/// there; a tap on the empty canvas clears the selection.
class FlowCanvas extends StatefulWidget {
  const FlowCanvas({
    required this.blocks,
    required this.wires,
    required this.actions,
    required this.onClear,
    required this.onMove,
    required this.onDrop,
    this.legend,
    super.key,
  });

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final FlowBlockActions actions;

  /// A tap on the empty canvas.
  final VoidCallback onClear;

  /// A block let go at (`x`, `y`).
  final void Function(String id, double x, double y) onMove;

  /// A palette entry (its id) dropped at a point of the canvas.
  final void Function(String entry, double x, double y) onDrop;
  final FlowLegendVm? legend;

  static const size = Size(3000, 2000);

  @override
  State<FlowCanvas> createState() => _FlowCanvasState();
}

class _FlowCanvasState extends State<FlowCanvas> {
  final _drag = <String, Offset>{};
  final GlobalKey<State<StatefulWidget>> _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = [
      for (final b in widget.blocks)
        if (_drag[b.id] case final at?) b.at(at.dx, at.dy) else b,
    ];
    final byId = {for (final b in blocks) b.id: b};
    final actions = FlowBlockActions(
      onSelect: widget.actions.onSelect,
      onBind: widget.actions.onBind,
      onUnbind: widget.actions.onUnbind,
      onDropEntry: widget.actions.onDropEntry,
      onResize: widget.actions.onResize,
      onMove: (id, delta) => setState(() {
        final b = byId[id];
        if (b == null) {
          return;
        }
        final at = _drag[id] ?? Offset(b.x, b.y);
        _drag[id] = Offset(
          (at.dx + delta.dx).clamp(0, FlowCanvas.size.width - b.width),
          (at.dy + delta.dy).clamp(0, FlowCanvas.size.height - 100),
        );
      }),
      onMoveEnd: (id) {
        final at = _drag.remove(id);
        if (at != null) {
          widget.onMove(id, at.dx, at.dy);
        }
      },
    );
    return ColoredBox(
      color: c.ground0,
      child: Stack(
        children: [
          Positioned.fill(
            child: DragTarget<Object>(
              onWillAcceptWithDetails: (d) => d.data is String,
              onAcceptWithDetails: (d) {
                final box =
                    _key.currentContext?.findRenderObject() as RenderBox?;
                final p = box?.globalToLocal(d.offset) ?? Offset.zero;
                widget.onDrop(d.data as String, p.dx, p.dy);
              },
              builder: (context, _, _) => InteractiveViewer(
                constrained: false,
                minScale: 0.4,
                maxScale: 1.6,
                boundaryMargin: const EdgeInsets.all(200),
                child: GestureDetector(
                  onTap: widget.onClear,
                  child: SizedBox(
                    key: _key,
                    width: FlowCanvas.size.width,
                    height: FlowCanvas.size.height,
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _Grid(c.line1),
                            foregroundPainter: _Wires(
                              wires: widget.wires,
                              byId: byId,
                              teal: c.good,
                              ember: c.ember,
                            ),
                          ),
                        ),
                        for (final w in widget.wires)
                          if (w.warning case final text?)
                            if (_mid(byId, w) case final m?)
                              Positioned(
                                left: m.dx - 60,
                                top: m.dy - 11,
                                width: 120,
                                child: Center(
                                  child: _WarnChip(text, w.warningNote),
                                ),
                              ),
                        for (final b in blocks)
                          Positioned(
                            left: b.x,
                            top: b.y,
                            child: FlowBlockView(
                              key: ValueKey(b.id),
                              vm: b,
                              actions: actions,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.legend case final l?)
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: IgnorePointer(
                child: Align(
                  alignment: .bottomLeft,
                  child: FlowLegend(vm: l),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The middle of [w]'s curve, if both its ends are drawn.
Offset? _mid(Map<String, FlowBlockVm> byId, FlowWireVm w) {
  final p1 = byId[w.from]?.portAt(w.fromPort, output: true);
  final p2 = byId[w.to]?.portAt(w.toPort, output: false);
  if (p1 == null || p2 == null) {
    return null;
  }
  final dx = _dx(p1, p2);
  // A cubic at t = 1/2: (p1 + 3 c1 + 3 c2 + p2) / 8.
  return Offset(
    (p1.dx + 3 * (p1.dx + dx) + 3 * (p2.dx - dx) + p2.dx) / 8,
    (p1.dy + 3 * p1.dy + 3 * p2.dy + p2.dy) / 8,
  );
}

double _dx(Offset p1, Offset p2) {
  final half = (p2.dx - p1.dx).abs() / 2;
  return half < 50 ? 50 : half;
}

/// The warning chip of a wire.
class _WarnChip extends StatelessWidget {
  const _WarnChip(this.text, this.note);

  final String text;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: note,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: .center,
        decoration: BoxDecoration(
          color: c.warnTint,
          border: .all(color: c.warnLine),
          borderRadius: const BorderRadius.all(Radius.circular(11)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: c.warn)),
      ),
    );
  }
}

/// A dot every 20 px (spec §1: radial #252B30, 1 px).
class _Grid extends CustomPainter {
  _Grid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 10.0; x < size.width; x += 20) {
      for (var y = 10.0; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Grid old) => old.color != color;
}

/// `M x1 y1 C x1+dx y1, x2−dx y2, x2 y2`, `dx = max(50, |x2−x1|/2)`,
/// width 2 (spec §4).
class _Wires extends CustomPainter {
  _Wires({
    required this.wires,
    required this.byId,
    required this.teal,
    required this.ember,
  });

  final List<FlowWireVm> wires;
  final Map<String, FlowBlockVm> byId;
  final Color teal;
  final Color ember;

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in wires) {
      final p1 = byId[w.from]?.portAt(w.fromPort, output: true);
      final p2 = byId[w.to]?.portAt(w.toPort, output: false);
      if (p1 == null || p2 == null) {
        continue;
      }
      final dx = _dx(p1, p2);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = w.writes ? ember : teal
          ..style = .stroke
          ..strokeCap = .round
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_Wires old) => old.wires != wires || old.byId != byId;
}
