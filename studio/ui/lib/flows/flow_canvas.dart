import 'package:equatable/equatable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'field_drop_zone.dart';
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
/// pinned bottom-left.
///
/// The canvas reads the pointer itself, in its own coordinates, so what is
/// dragged stays under the pointer at any zoom and scroll:
/// - a block's header moves the block (snapped to the 20 px grid when let
///   go);
/// - a field, after 3 px, draws a wire from its right port to the pointer;
///   a row that takes it lights, one that refuses lights red with the
///   reason; let go on a row that takes it, it binds; on the empty canvas,
///   nothing happens;
/// - on a bound input, the left port (or the whole row of a field without
///   an output) picks its wire up: let go on another input, it moves
///   there; on the empty canvas, it unbinds;
/// - a double click or an Alt-click on a bound input unbinds it;
/// - the pointer over a bound field lights its wire and its source row (the
///   field shows the value that comes in, not where it comes from);
/// - the empty canvas pans, and so do two fingers on a trackpad; a click
///   on it clears the selection.
///
/// A wire let go outside the canvas over a [FieldDropZone] (the inspector)
/// binds that field. A palette entry dropped on the canvas places a block
/// with the pointer on its header.
class FlowCanvas extends StatefulWidget {
  const FlowCanvas({
    required this.blocks,
    required this.wires,
    required this.actions,
    required this.onClear,
    required this.onMove,
    required this.onDrop,
    this.legend,
    this.controller,
    super.key,
  });

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final FlowBlockActions actions;

  /// A tap on the empty canvas.
  final VoidCallback onClear;

  /// A block let go at (`x`, `y`), on the grid.
  final void Function(String id, double x, double y) onMove;

  /// A palette entry (its id) dropped: the new block's top-left, on the
  /// grid.
  final void Function(String entry, double x, double y) onDrop;
  final FlowLegendVm? legend;

  /// The zoom and scroll; the canvas keeps its own when none is given.
  final TransformationController? controller;

  static const size = Size(3000, 2000);

  /// The grid blocks snap to.
  static const grid = 20.0;

  /// Where a dropped block's top-left goes relative to the pointer: the
  /// pointer lands on the header, past the kind chip.
  static const dropGrab = Offset(24, 16);

  /// How far the pointer moves, on the screen, before a press drags.
  static const slop = 3.0;

  static double snap(double v) => (v / grid).round() * grid;

  @override
  State<FlowCanvas> createState() => _FlowCanvasState();
}

/// What a press on the canvas started.
sealed class _Press {
  _Press(this.down);

  /// Where it went down, on the screen.
  final Offset down;
  var dragging = false;
}

final class _Pan extends _Press {
  _Pan(super.down);
}

final class _Move extends _Press {
  _Move(super.down, this.id, this.grab);

  final String id;

  /// The pointer's place on the block, kept while it moves.
  final Offset grab;
  Offset? at;
}

final class _Wire extends _Press {
  _Wire(super.down, this.from, {this.picked});

  /// The output the wire comes from.
  final FieldRefVm from;

  /// The input a picked-up wire leaves: block, port and row.
  final (String, String, String)? picked;
  Offset pointer = Offset.zero;

  /// The row under the pointer: block and row id; with [refusal] when it
  /// refuses.
  (String, String)? over;
  String? refusal;

  /// The field outside the canvas under the pointer.
  FieldDrop? outside;
}

/// A press that only selects (a field with nothing to drag, the body).
final class _Tap extends _Press {
  _Tap(super.down, this.block, this.row);

  final String block;
  final String? row;
}

class _FlowCanvasState extends State<FlowCanvas> {
  final GlobalKey<State<StatefulWidget>> _key = GlobalKey();
  final GlobalKey<State<StatefulWidget>> _view = GlobalKey();
  TransformationController? _own;
  _Press? _press;

  /// The last click on a row, for a double click: block, row, when.
  (String, String, Duration)? _lastClick;

  /// The bound field under the pointer: block and row id.
  (String, String)? _hover;

  TransformationController get _ctl =>
      widget.controller ?? (_own ??= TransformationController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// The blocks as drawn: the moving one where the pointer has it.
  List<FlowBlockVm> get _blocks => [
    for (final b in widget.blocks)
      if (_press case _Move(:final id, :final at?) when id == b.id)
        b.at(at.dx, at.dy)
      else
        b,
  ];

  Offset _local(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  bool _inView(Offset global) {
    final box = _view.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return true;
    }
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  /// The topmost block under [p] (canvas coordinates).
  FlowBlockVm? _blockAt(List<FlowBlockVm> blocks, Offset p) {
    for (final b in blocks.reversed) {
      if (b.contains(p)) {
        return b;
      }
    }
    return null;
  }

  static bool _bound(FieldRowVm r) =>
      r.inPort != null &&
      (r.inMark == PortMark.bound || r.inMark == PortMark.write);

  void _hoverAt(PointerHoverEvent e) {
    final p = e.localPosition;
    final b = _blockAt(_blocks, p);
    final i = b?.rowAt(p);
    final next = b != null && i != null && _bound(b.rows[i])
        ? (b.id, b.rows[i].id)
        : null;
    if (next != _hover) {
      setState(() => _hover = next);
    }
  }

  /// The wire into the bound field under the pointer.
  FlowWireVm? _hovered(Map<String, FlowBlockVm> byId) {
    final h = _hover;
    if (h == null) {
      return null;
    }
    final port = byId[h.$1]?.rows
        .where((r) => r.id == h.$2)
        .firstOrNull
        ?.inPort;
    return widget.wires
        .where((w) => w.to == h.$1 && w.toPort == port)
        .firstOrNull;
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) {
      return;
    }
    final p = e.localPosition;
    final blocks = _blocks;
    final b = _blockAt(blocks, p);
    if (b == null) {
      _press = _Pan(e.position);
      return;
    }
    widget.actions.onSelect(b.id);
    if (b.onHeader(p)) {
      _press = _Move(e.position, b.id, p - Offset(b.x, b.y));
      return;
    }
    final i = b.rowAt(p);
    if (i == null) {
      _press = _Tap(e.position, b.id, null);
      return;
    }
    final r = b.rows[i];
    if (_bound(r) && HardwareKeyboard.instance.isAltPressed) {
      _press = null;
      widget.actions.onUnbind(b.id, r.id);
      return;
    }
    if (_bound(r) && (b.onLeftPort(p) || r.outPort == null)) {
      final w = widget.wires
          .where((w) => w.to == b.id && w.toPort == r.inPort)
          .firstOrNull;
      if (w != null) {
        _press = _Wire(
          e.position,
          FieldRefVm(w.from, w.fromPort),
          picked: (b.id, r.inPort!, r.id),
        )..pointer = p;
        return;
      }
    }
    if (r.outPort case final out?) {
      _press = _Wire(
        e.position,
        FieldRefVm(b.id, out, label: '${b.id}.${r.label}'),
      )..pointer = p;
      return;
    }
    _press = _Tap(e.position, b.id, r.id);
  }

  void _move(PointerMoveEvent e) {
    final press = _press;
    if (press == null) {
      return;
    }
    if (!press.dragging &&
        (e.position - press.down).distance < FlowCanvas.slop) {
      return;
    }
    press.dragging = true;
    final p = e.localPosition;
    switch (press) {
      case _Pan():
        _ctl.value = Matrix4.translationValues(e.delta.dx, e.delta.dy, 0)
          ..multiply(_ctl.value);
      case _Move(:final id, :final grab):
        final b = widget.blocks.where((b) => b.id == id).firstOrNull;
        if (b == null) {
          return;
        }
        final at = p - grab;
        setState(
          () => press.at = Offset(
            at.dx.clamp(0, FlowCanvas.size.width - b.width),
            at.dy.clamp(0, FlowCanvas.size.height - b.height),
          ),
        );
      case _Wire():
        _follow(press, p, e.position);
      case _Tap():
        break;
    }
  }

  void _follow(_Wire w, Offset p, Offset global) {
    w
      ..pointer = p
      ..over = null
      ..refusal = null
      ..outside = null;
    if (!_inView(global)) {
      // A picked-up wire moves between inputs of the canvas only.
      w.outside = w.picked != null
          ? null
          : fieldDropAt(global, View.of(context).viewId);
    } else {
      final b = _blockAt(_blocks, p);
      final i = b?.rowAt(p);
      if (b != null && i != null) {
        final r = b.rows[i];
        final picked = w.picked;
        final same = picked != null && picked.$1 == b.id && picked.$3 == r.id;
        w
          ..over = (b.id, r.id)
          ..refusal = same
              ? null
              : widget.actions.refusal(
                  w.from,
                  b.id,
                  r.id,
                  replacing: picked == null ? null : (picked.$1, picked.$2),
                );
      }
    }
    fieldDropHover.value = w.outside?.id;
    setState(() {});
  }

  void _up(PointerUpEvent e) {
    final press = _press;
    _press = null;
    fieldDropHover.value = null;
    switch (press) {
      case null:
        return;
      case _Pan(:final dragging):
        if (!dragging) {
          widget.onClear();
        }
      case _Move(:final id, :final at?):
        widget.onMove(id, FlowCanvas.snap(at.dx), FlowCanvas.snap(at.dy));
      case _Move():
        break;
      case _Wire(dragging: false, picked: (final block, _, final row)):
        _click(block, row);
      case _Wire(dragging: false, :final from):
        final b = _blockAt(_blocks, e.localPosition);
        final i = b?.rowAt(e.localPosition);
        if (b != null && i != null) {
          _click(b.id, b.rows[i].id);
        } else {
          _click(from.block, '');
        }
      case _Wire():
        _drop(press);
      case _Tap(:final block, :final row?):
        _click(block, row);
      case _Tap():
        break;
    }
    setState(() {});
  }

  void _drop(_Wire w) {
    final picked = w.picked;
    if (w.outside case final zone?) {
      zone.onDrop(w.from);
      return;
    }
    final over = w.over;
    if (over == null) {
      // Let go on the canvas, not on a field: a picked-up wire unbinds.
      final onBlock = _blockAt(_blocks, w.pointer) != null;
      if (picked != null && !onBlock) {
        widget.actions.onUnbind(picked.$1, picked.$3);
      }
      return;
    }
    if (w.refusal != null) {
      return;
    }
    final (block, rowId) = over;
    final row = _blocks
        .where((b) => b.id == block)
        .firstOrNull
        ?.rows
        .where((r) => r.id == rowId)
        .firstOrNull;
    final inPort = row?.inPort;
    if (inPort == null) {
      return;
    }
    if (picked == null) {
      widget.actions.onBind(w.from, block, inPort);
    } else if (picked.$1 != block || picked.$2 != inPort) {
      widget.actions.onRebind(picked.$1, picked.$2, block, inPort);
    }
  }

  /// A click on row [row] of [block]; the second within 400 ms on a bound
  /// input unbinds it.
  void _click(String block, String row) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastClick;
    _lastClick = (block, row, now);
    if (last == null ||
        last.$1 != block ||
        last.$2 != row ||
        row.isEmpty ||
        now - last.$3 > const Duration(milliseconds: 400)) {
      return;
    }
    _lastClick = null;
    final r = widget.blocks
        .where((b) => b.id == block)
        .firstOrNull
        ?.rows
        .where((r) => r.id == row)
        .firstOrNull;
    if (r != null && _bound(r)) {
      widget.actions.onUnbind(block, row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = _blocks;
    final byId = {for (final b in blocks) b.id: b};
    final wire = switch (_press) {
      final _Wire w when w.dragging => w,
      _ => null,
    };
    final picked = wire?.picked;
    final wires = [
      for (final w in widget.wires)
        if (picked == null || w.to != picked.$1 || w.toPort != picked.$2) w,
    ];
    final selected = blocks.where((b) => b.selected).firstOrNull?.id;
    final front = [
      for (final w in wires)
        if (w.from == selected || w.to == selected) w,
    ];
    final light = wire?.over == null
        ? RowLight.none
        : (wire!.refusal == null ? RowLight.takes : RowLight.refuses);
    final pending = wire == null ? null : _pending(wire, byId);
    // The pointer over a bound field: its wire over the blocks, its source
    // row lit.
    final hovered = _press == null ? _hovered(byId) : null;
    final source = hovered == null
        ? null
        : byId[hovered.from]?.rows
              .where((r) => r.sends(hovered.fromPort))
              .firstOrNull
              ?.id;
    if (hovered != null && !front.contains(hovered)) {
      front.add(hovered);
    }
    return MouseRegion(
      onExit: (_) {
        if (_hover != null) {
          setState(() => _hover = null);
        }
      },
      child: ColoredBox(
        key: _view,
        color: c.ground0,
        child: Stack(
          children: [
            Positioned.fill(
              child: DragTarget<String>(
                onAcceptWithDetails: (d) {
                  final p = _local(d.offset) - FlowCanvas.dropGrab;
                  widget.onDrop(
                    d.data,
                    FlowCanvas.snap(p.dx.clamp(0, FlowCanvas.size.width)),
                    FlowCanvas.snap(p.dy.clamp(0, FlowCanvas.size.height)),
                  );
                },
                builder: (context, _, _) => InteractiveViewer(
                  transformationController: _ctl,
                  constrained: false,
                  panEnabled: false,
                  minScale: 0.4,
                  maxScale: 1.6,
                  boundaryMargin: const EdgeInsets.all(200),
                  child: Listener(
                    behavior: .opaque,
                    onPointerHover: _hoverAt,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    // Two fingers on a trackpad scroll the canvas; the viewer
                    // keeps pinch zoom.
                    onPointerPanZoomUpdate: (e) =>
                        _ctl.value = Matrix4.translationValues(
                          e.panDelta.dx,
                          e.panDelta.dy,
                          0,
                        )..multiply(_ctl.value),
                    onPointerCancel: (_) => setState(() {
                      _press = null;
                      fieldDropHover.value = null;
                    }),
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
                                wires: wires,
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
                              child: FlowBlockView(
                                key: ValueKey(b.id),
                                vm: b,
                                actions: widget.actions,
                                lit: wire?.over?.$1 == b.id
                                    ? wire!.over!.$2
                                    : (hovered?.from == b.id ? source : null),
                                light: wire?.over?.$1 == b.id
                                    ? light
                                    : RowLight.source,
                              ),
                            ),
                          // The selected block's wires over the blocks.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _Wires(
                                  wires: front,
                                  byId: byId,
                                  teal: c.good,
                                  ember: c.ember,
                                  pending: pending,
                                  pendingColor: wire?.refusal != null
                                      ? c.bad
                                      : c.good,
                                  highlight: hovered,
                                ),
                              ),
                            ),
                          ),
                          for (final w in wires)
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
                          if (wire?.refusal case final why?)
                            Positioned(
                              left: wire!.pointer.dx + 14,
                              top: wire.pointer.dy + 12,
                              child: IgnorePointer(child: _Refusal(why)),
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
      ),
    );
  }

  /// The wire being dragged: from its output's port to the input it is
  /// over (when that takes it), else to the pointer.
  (Offset, Offset)? _pending(_Wire w, Map<String, FlowBlockVm> byId) {
    final p1 = byId[w.from.block]?.portAt(w.from.port, output: true);
    if (p1 == null) {
      return null;
    }
    var p2 = w.pointer;
    if (w.over case (final block, final row) when w.refusal == null) {
      final b = byId[block];
      final r = b?.rows.where((r) => r.id == row).firstOrNull;
      if (r?.inPort case final port?) {
        p2 = b!.portAt(port, output: false) ?? p2;
      }
    }
    return (p1, p2);
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

/// Why the row under a dragged wire refuses it, beside the pointer.
class _Refusal extends StatelessWidget {
  const _Refusal(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: .center,
      decoration: BoxDecoration(
        color: c.badTint,
        border: .all(color: c.badLine),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(text, style: mono(size: 11, color: c.bad)),
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
/// width 2 (spec §4); [pending] is the wire being dragged.
class _Wires extends CustomPainter {
  _Wires({
    required this.wires,
    required this.byId,
    required this.teal,
    required this.ember,
    this.pending,
    this.pendingColor = Colors.transparent,
    this.highlight,
  });

  final List<FlowWireVm> wires;

  /// The wire of the bound field under the pointer: drawn wider.
  final FlowWireVm? highlight;
  final Map<String, FlowBlockVm> byId;
  final Color teal;
  final Color ember;
  final (Offset, Offset)? pending;
  final Color pendingColor;

  static Path _curve(Offset p1, Offset p2) {
    final dx = _dx(p1, p2);
    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in wires) {
      final p1 = byId[w.from]?.portAt(w.fromPort, output: true);
      final p2 = byId[w.to]?.portAt(w.toPort, output: false);
      if (p1 == null || p2 == null) {
        continue;
      }
      final lit = w == highlight;
      final color = w.writes ? ember : teal;
      if (lit) {
        canvas.drawPath(
          _curve(p1, p2),
          Paint()
            ..color = color.withValues(alpha: 0.25)
            ..style = .stroke
            ..strokeCap = .round
            ..strokeWidth = 8,
        );
      }
      canvas.drawPath(
        _curve(p1, p2),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeCap = .round
          ..strokeWidth = lit ? 3 : 2,
      );
    }
    if (pending case (final p1, final p2)) {
      canvas
        ..drawPath(
          _curve(p1, p2),
          Paint()
            ..color = pendingColor
            ..style = .stroke
            ..strokeCap = .round
            ..strokeWidth = 2,
        )
        ..drawCircle(p2, 4, Paint()..color = pendingColor);
    }
  }

  @override
  bool shouldRepaint(_Wires old) =>
      old.wires != wires ||
      old.byId != byId ||
      old.pending != pending ||
      old.pendingColor != pendingColor ||
      old.highlight != highlight;
}
