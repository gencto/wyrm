import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One port row of a block.
final class PortVm extends Equatable {
  const PortVm({required this.name, this.value = '', this.wired = false});

  final String name;

  /// The parameter's value or the live value, shown on the right.
  final String value;
  final bool wired;

  @override
  List<Object?> get props => [name, value, wired];
}

/// One block on the canvas.
final class FlowBlockVm extends Equatable {
  const FlowBlockVm({
    required this.id,
    required this.title,
    required this.tag,
    required this.x,
    required this.y,
    this.subtitle = '',
    this.tone = Tone.neutral,
    this.inputs = const [],
    this.outputs = const [],
    this.selected = false,
    this.footer,
    this.footerTone = Tone.good,
  });

  final String id;

  /// The block id; [subtitle] its type.
  final String title;
  final String subtitle;

  /// `IN`, `OUT`, `FX`.
  final String tag;

  /// good (IN, teal), ember (OUT), neutral (logic).
  final Tone tone;
  final double x;
  final double y;
  final List<PortVm> inputs;
  final List<PortVm> outputs;
  final bool selected;

  /// The live value with its quality.
  final String? footer;
  final Tone footerTone;

  @override
  List<Object?> get props => [
    id,
    title,
    subtitle,
    tag,
    tone,
    x,
    y,
    inputs,
    outputs,
    selected,
    footer,
    footerTone,
  ];
}

/// One wire: `<from>.<fromPort>` → `<to>.<toPort>`.
final class FlowWireVm extends Equatable {
  const FlowWireVm(this.from, this.fromPort, this.to, this.toPort);

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  @override
  List<Object?> get props => [from, fromPort, to, toPort];
}

/// Board *Flow editor · fields, bindings, properties*: blocks with one row
/// per port on a dotted grid, S-curve wires (teal into a block, ember
/// into a block that writes). Drag a block by its header; tap an output,
/// then an input, to wire them; double tap an input to unwire it; drop a
/// palette entry to add a block.
class FlowCanvas extends StatefulWidget {
  const FlowCanvas({
    required this.blocks,
    required this.wires,
    required this.onSelect,
    required this.onMove,
    required this.onConnect,
    required this.onDisconnect,
    required this.onDrop,
    super.key,
  });

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final ValueChanged<String?> onSelect;
  final void Function(String id, double x, double y) onMove;
  final void Function(String from, String fromPort, String to, String toPort)
  onConnect;
  final void Function(String to, String toPort) onDisconnect;

  /// A palette entry (its id) dropped at a point of the canvas.
  final void Function(String entry, double x, double y) onDrop;

  static const blockWidth = 230.0;
  static const headerHeight = 38.0;
  static const rowHeight = 28.0;
  static const size = Size(3000, 2000);

  @override
  State<FlowCanvas> createState() => _FlowCanvasState();
}

class _FlowCanvasState extends State<FlowCanvas> {
  (String, String)? _pending;
  final _drag = <String, Offset>{};
  final GlobalKey<State<StatefulWidget>> _key = GlobalKey();

  static Offset portAt(FlowBlockVm b, String port, {required bool output}) {
    final list = output ? b.outputs : b.inputs;
    final i = list.indexWhere((p) => p.name == port);
    final row = output ? b.inputs.length + i : i;
    return Offset(
      b.x + (output ? FlowCanvas.blockWidth : 0),
      b.y +
          FlowCanvas.headerHeight +
          8 +
          FlowCanvas.rowHeight * row +
          FlowCanvas.rowHeight / 2,
    );
  }

  FlowBlockVm _at(FlowBlockVm b) {
    final d = _drag[b.id];
    return d == null
        ? b
        : FlowBlockVm(
            id: b.id,
            title: b.title,
            subtitle: b.subtitle,
            tag: b.tag,
            tone: b.tone,
            x: d.dx,
            y: d.dy,
            inputs: b.inputs,
            outputs: b.outputs,
            selected: b.selected,
            footer: b.footer,
            footerTone: b.footerTone,
          );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = [for (final b in widget.blocks) _at(b)];
    final byId = {for (final b in blocks) b.id: b};
    return DragTarget<String>(
      onAcceptWithDetails: (d) {
        final box = _key.currentContext?.findRenderObject() as RenderBox?;
        final p = box?.globalToLocal(d.offset) ?? Offset.zero;
        widget.onDrop(d.data, p.dx, p.dy);
      },
      builder: (context, _, _) => InteractiveViewer(
        constrained: false,
        minScale: 0.4,
        maxScale: 1.6,
        boundaryMargin: const EdgeInsets.all(200),
        child: GestureDetector(
          onTap: () {
            setState(() => _pending = null);
            widget.onSelect(null);
          },
          child: SizedBox(
            key: _key,
            width: FlowCanvas.size.width,
            height: FlowCanvas.size.height,
            child: Stack(
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
                for (final b in blocks)
                  Positioned(
                    left: b.x,
                    top: b.y,
                    width: FlowCanvas.blockWidth,
                    child: _Block(
                      vm: b,
                      pending: _pending,
                      onTap: () => widget.onSelect(b.id),
                      onDrag: (delta) => setState(() {
                        final at = _drag[b.id] ?? Offset(b.x, b.y);
                        _drag[b.id] = Offset(
                          (at.dx + delta.dx).clamp(
                            0,
                            FlowCanvas.size.width - FlowCanvas.blockWidth,
                          ),
                          (at.dy + delta.dy).clamp(
                            0,
                            FlowCanvas.size.height - 100,
                          ),
                        );
                      }),
                      onDragEnd: () {
                        final at = _drag.remove(b.id);
                        if (at != null) {
                          widget.onMove(b.id, at.dx, at.dy);
                        }
                      },
                      onOutput: (port) =>
                          setState(() => _pending = (b.id, port)),
                      onInput: (port) {
                        final p = _pending;
                        if (p != null) {
                          widget.onConnect(p.$1, p.$2, b.id, port);
                          setState(() => _pending = null);
                        }
                      },
                      onUnwire: (port) => widget.onDisconnect(b.id, port),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.vm,
    required this.pending,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
    required this.onOutput,
    required this.onInput,
    required this.onUnwire,
  });

  final FlowBlockVm vm;
  final (String, String)? pending;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<String> onOutput;
  final ValueChanged<String> onInput;
  final ValueChanged<String> onUnwire;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (tagBg, tagFg) = switch (vm.tone) {
      .good => (c.goodTint, c.good),
      .ember => (c.emberTint, c.emberSoft),
      _ => (c.ground4, c.text2),
    };
    Widget port(PortVm p, {required bool output}) {
      final waiting = pending != null && !output;
      final mine = pending == (vm.id, p.name);
      final dot = GestureDetector(
        onTap: () => output ? onOutput(p.name) : onInput(p.name),
        onDoubleTap: output ? null : () => onUnwire(p.name),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: .circle,
            color: p.wired || mine ? (output ? c.good : c.good) : c.ground1,
            border: .all(
              color: mine ? c.ember : (waiting ? c.emberSoft : c.text4),
              width: 1.5,
            ),
          ),
        ),
      );
      return SizedBox(
        height: FlowCanvas.rowHeight,
        child: Row(
          children: [
            Transform.translate(
              offset: const Offset(-7, 0),
              child: output ? const SizedBox(width: 14) : dot,
            ),
            Expanded(
              child: Text(
                '${p.name}:',
                overflow: .ellipsis,
                style: mono(size: 12, color: c.text3),
              ),
            ),
            if (p.value.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  p.value,
                  overflow: .ellipsis,
                  textAlign: .right,
                  style: mono(size: 12, color: output ? c.emberNew : c.text1),
                ),
              ),
            Transform.translate(
              offset: const Offset(7, 0),
              child: output ? dot : const SizedBox(width: 14),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: vm.selected ? const Color(0xFF1A1D1F) : c.ground2,
          border: .all(
            color: vm.selected ? c.ember : c.line2,
            width: vm.selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            GestureDetector(
              onPanUpdate: (d) => onDrag(d.delta),
              onPanEnd: (_) => onDragEnd(),
              child: Container(
                height: FlowCanvas.headerHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: vm.tone == .good
                      ? c.goodTint.withValues(alpha: 0.5)
                      : (vm.tone == .ember ? c.emberTint : null),
                  border: Border(bottom: BorderSide(color: c.line1)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: tagBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        vm.tag,
                        style: mono(size: 10, weight: .w600, color: tagFg),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        vm.title,
                        overflow: .ellipsis,
                        style: mono(weight: .w600, color: c.text1),
                      ),
                    ),
                    Text(
                      vm.subtitle,
                      style: TextStyle(fontSize: 11, color: c.text4),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final p in vm.inputs) port(p, output: false),
                  for (final p in vm.outputs) port(p, output: true),
                ],
              ),
            ),
            if (vm.footer case final f?)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line1)),
                ),
                child: Text(
                  f,
                  overflow: .ellipsis,
                  style: mono(
                    size: 12,
                    color: switch (vm.footerTone) {
                      .bad => c.bad,
                      .warn => c.warn,
                      _ => c.good,
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends CustomPainter {
  _Grid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 24) {
      for (var y = 0.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Grid old) => old.color != color;
}

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
      final a = byId[w.from];
      final b = byId[w.to];
      if (a == null || b == null) {
        continue;
      }
      final p1 = _FlowCanvasState.portAt(a, w.fromPort, output: true);
      final p2 = _FlowCanvasState.portAt(b, w.toPort, output: false);
      final dx = ((p2.dx - p1.dx).abs() / 2).clamp(40, 200).toDouble();
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = b.tone == .ember ? ember : teal
          ..style = .stroke
          ..strokeWidth = 1.8,
      );
    }
  }

  @override
  bool shouldRepaint(_Wires old) => old.wires != wires || old.byId != byId;
}
