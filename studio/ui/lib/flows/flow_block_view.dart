import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What a block is (spec §3 header chip): a point of the tree, logic, a
/// sink, an action of the tree, an own block.
enum BlockKindVm {
  node('NODE'),
  logic('FX'),
  sink('OUT'),
  action('ACT'),
  my('MY');

  const BlockKindVm(this.chip);

  final String chip;
}

/// How a port is drawn: absent, free (grey ring), bound (teal), bound by a
/// write into a device (ember).
enum PortMark { none, free, bound, write }

/// The colour of a field's value: plain, bound (from another field), bad
/// quality.
enum ValueTone { plain, bound, bad }

/// A field one drags from: block [block], engine output [port].
final class FieldRefVm extends Equatable {
  const FieldRefVm(this.block, this.port, {this.label = ''});

  final String block;
  final String port;

  /// `case.output`, shown while dragging.
  final String label;

  @override
  List<Object?> get props => [block, port, label];
}

/// One field of a block: one row, 28 high.
final class FieldRowVm extends Equatable {
  const FieldRowVm({
    required this.id,
    required this.label,
    this.name = '',
    this.value = '',
    this.tone = ValueTone.plain,
    this.inPort,
    this.outPort,
    this.inMark = PortMark.none,
    this.outMark = PortMark.none,
    this.dropTarget = false,
  });

  /// The field's id within its block.
  final String id;

  /// What the row reads: `Input min`, `Input 1`, a point's name; no colon.
  final String label;

  /// What the engine calls it (`input_min`, `in.0`): the row's tooltip.
  final String name;

  /// Already formatted (`92.6`, `4095`, `82.5 °C`).
  final String value;
  final ValueTone tone;

  /// The engine input a binding into it uses; null: no left port.
  final String? inPort;

  /// The engine output a binding out of it uses; null: no right port.
  final String? outPort;
  final PortMark inMark;
  final PortMark outMark;

  /// Lit as where a dragged point lands (dashed ember box).
  final bool dropTarget;

  @override
  List<Object?> get props => [
    id,
    label,
    name,
    value,
    tone,
    inPort,
    outPort,
    inMark,
    outMark,
    dropTarget,
  ];
}

/// The − / + row of a block with variable inputs.
final class VariadicVm extends Equatable {
  const VariadicVm({
    required this.label,
    this.canRemove = true,
    this.canAdd = true,
    this.removeLabel = 'Remove the last input',
    this.addLabel = 'Add an input',
  });

  /// `2 inputs`, `3 cases`.
  final String label;
  final bool canRemove;
  final bool canAdd;
  final String removeLabel;
  final String addLabel;

  @override
  List<Object?> get props => [
    label,
    canRemove,
    canAdd,
    removeLabel,
    addLabel,
  ];
}

/// One block on the canvas.
final class FlowBlockVm extends Equatable {
  const FlowBlockVm({
    required this.id,
    required this.title,
    required this.x,
    required this.y,
    this.type = '',
    this.kind = BlockKindVm.logic,
    this.width = 220,
    this.rows = const [],
    this.variadic,
    this.selected = false,
  });

  final String id;

  /// The node id, mono.
  final String title;

  /// On the right of the header: the type (`scale`), or the connection of a
  /// tree point (`modbus/tcp-tank`).
  final String type;
  final BlockKindVm kind;
  final double x;
  final double y;

  /// 200–220 (spec §3).
  final double width;
  final List<FieldRowVm> rows;
  final VariadicVm? variadic;
  final bool selected;

  FlowBlockVm at(double x, double y) => FlowBlockVm(
    id: id,
    title: title,
    x: x,
    y: y,
    type: type,
    kind: kind,
    width: width,
    rows: rows,
    variadic: variadic,
    selected: selected,
  );

  static const headerHeight = 32.0;
  static const rowHeight = 28.0;
  static const bodyTop = 6.0;

  /// The − / + row under the fields.
  static const toolsHeight = 38.0;

  /// How tall the block is drawn: header, body padding 6 + 8, 28 per row
  /// (at least one), the − / + row.
  double get height =>
      headerHeight +
      bodyTop +
      rowHeight * (rows.isEmpty ? 1 : rows.length) +
      8 +
      (variadic == null ? 0 : toolsHeight);

  /// Whether [p] (canvas coordinates) is on the header, which moves the
  /// block.
  bool onHeader(Offset p) =>
      p.dx >= x && p.dx <= x + width && p.dy >= y && p.dy < y + headerHeight;

  /// Whether [p] is on the block, its ports included (they stand 5 px out).
  bool contains(Offset p) =>
      p.dx >= x - 8 && p.dx <= x + width + 8 && p.dy >= y && p.dy <= y + height;

  /// The row under [p], if any.
  int? rowAt(Offset p) {
    if (!contains(p)) {
      return null;
    }
    final i = ((p.dy - y - headerHeight - bodyTop) / rowHeight).floor();
    return i >= 0 && i < rows.length ? i : null;
  }

  /// Whether [p] is on the left port's side of a row: the port and the
  /// 14 px inside it. A press there on a bound input picks its wire up.
  bool onLeftPort(Offset p) => p.dx < x + 14;

  /// Where a wire meets [port] (an input: the left edge, an output: the
  /// right edge), at the centre of its row.
  Offset? portAt(String port, {required bool output}) {
    final i = rows.indexWhere(
      (r) => (output ? r.outPort : r.inPort) == port,
    );
    if (i < 0) {
      return null;
    }
    return Offset(
      x + (output ? width : 0),
      y + headerHeight + bodyTop + rowHeight * i + rowHeight / 2,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    type,
    kind,
    x,
    y,
    width,
    rows,
    variadic,
    selected,
  ];
}

/// What a block reports back; one set of handlers for every block, keyed by
/// [FlowBlockVm.id]. The canvas reads the pointer itself (drag a block by
/// its header, drag a wire from a field) and calls these.
final class FlowBlockActions {
  const FlowBlockActions({
    required this.onSelect,
    required this.onBind,
    required this.onRebind,
    required this.onUnbind,
    required this.onDropEntry,
    required this.onResize,
    this.refusal = _takesAll,
  });

  final ValueChanged<String> onSelect;

  /// A wire dragged from `from` let go on input `toPort` of `block`.
  final void Function(FieldRefVm from, String block, String toPort) onBind;

  /// The wire into `oldBlock.oldPort`, picked up and let go on input
  /// `toPort` of `block`.
  final void Function(
    String oldBlock,
    String oldPort,
    String block,
    String toPort,
  )
  onRebind;

  /// Double click or Alt-click on a bound input, or its wire picked up and
  /// let go on the empty canvas.
  final void Function(String block, String rowId) onUnbind;

  /// A palette entry (`key:<point>`) dropped on input `toPort` of `block`.
  final void Function(String entry, String block, String toPort) onDropEntry;

  /// − (false) or + (true).
  final void Function(String block, {required bool add}) onResize;

  /// Why a row (block, row id) does not take a wire from a field
  /// (`Outputs cannot be bound`, `number does not fit bool`), null when it
  /// does; `replacing` is the input a picked-up wire leaves.
  final String? Function(
    FieldRefVm from,
    String block,
    String rowId, {
    (String, String)? replacing,
  })
  refusal;

  static String? _takesAll(
    FieldRefVm from,
    String block,
    String rowId, {
    (String, String)? replacing,
  }) => null;
}

/// How a row is lit while a wire is dragged over it.
enum RowLight { none, takes, refuses }

/// A block of the flow editor (spec §3): a header with its kind chip, mono
/// title and type, then one row per field with its value and ports. The
/// canvas moves it and draws wires from and into its rows; a row with an
/// input takes a point dropped from the Tree tab. [lit] is the row a
/// dragged wire is over, [light] how it is lit.
class FlowBlockView extends StatelessWidget {
  const FlowBlockView({
    required this.vm,
    required this.actions,
    this.lit,
    this.light = RowLight.none,
    super.key,
  });

  final FlowBlockVm vm;
  final FlowBlockActions actions;
  final String? lit;
  final RowLight light;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (headerFill, ink) = switch (vm.kind) {
      .node => (c.goodTint, c.good),
      .logic => (c.ground4, c.text2),
      .sink => (c.ground4, c.emberSoft),
      .action => (c.emberTint, c.emberSoft),
      .my => (const Color(0xFF3A2A1C), c.emberSoft),
    };
    return Container(
      width: vm.width,
      decoration: BoxDecoration(
        color: c.ground2,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: .all(
          color: vm.selected ? c.ember : c.line2,
          width: vm.selected ? 1.5 : 1,
        ),
        boxShadow: [
          if (vm.selected)
            BoxShadow(color: c.ember.withValues(alpha: 0.14), spreadRadius: 4),
          BoxShadow(
            color: Colors.black.withValues(alpha: vm.selected ? 0.4 : 0.35),
            offset: Offset(0, vm.selected ? 10 : 8),
            blurRadius: vm.selected ? 24 : 20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Container(
              height: FlowBlockVm.headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: headerFill,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: .all(color: ink),
                      borderRadius: const BorderRadius.all(Radius.circular(3)),
                    ),
                    child: Text(
                      vm.kind.chip,
                      style: mono(
                        size: 9,
                        weight: .w600,
                        color: ink,
                      ).copyWith(height: 1.2),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: vm.width * 0.55),
                    child: Text(
                      vm.title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: mono(weight: .w600, color: c.text1),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      vm.type,
                      maxLines: 1,
                      overflow: .ellipsis,
                      textAlign: .right,
                      style: mono(size: 11, color: c.text4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: FlowBlockVm.bodyTop, bottom: 8),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (vm.rows.isEmpty)
                  const SizedBox(height: FlowBlockVm.rowHeight),
                for (final r in vm.rows)
                  _FieldRow(
                    block: vm.id,
                    vm: r,
                    actions: actions,
                    light: r.id == lit ? light : RowLight.none,
                  ),
                if (vm.variadic case final v?)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    padding: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line1)),
                    ),
                    child: Row(
                      spacing: 6,
                      children: [
                        _ToolButton(
                          label: '−',
                          tooltip: v.removeLabel,
                          onTap: v.canRemove
                              ? () => actions.onResize(vm.id, add: false)
                              : null,
                        ),
                        _ToolButton(
                          label: '+',
                          tooltip: v.addLabel,
                          onTap: v.canAdd
                              ? () => actions.onResize(vm.id, add: true)
                              : null,
                        ),
                        Text(
                          v.label,
                          style: TextStyle(fontSize: 12, color: c.text4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One field: its label, its value right-aligned, a port on each edge.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.block,
    required this.vm,
    required this.actions,
    required this.light,
  });

  final String block;
  final FieldRowVm vm;
  final FlowBlockActions actions;
  final RowLight light;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget dot(PortMark m) {
      final (fill, ring) = switch (m) {
        .none => (Colors.transparent, Colors.transparent),
        .free => (Colors.transparent, c.muted),
        .bound => (c.good, c.good),
        .write => (c.ember, c.ember),
      };
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: .circle,
          color: fill,
          border: .all(color: ring, width: 2),
        ),
      );
    }

    Widget row(RowLight light, {bool point = false}) => SizedBox(
      height: FlowBlockVm.rowHeight,
      child: Stack(
        clipBehavior: .none,
        children: [
          if (point || light != RowLight.none)
            Positioned.fill(
              child: CustomPaint(
                painter: switch (light) {
                  RowLight.refuses => _Dashed(
                    color: c.badLine,
                    fill: c.bad.withValues(alpha: 0.12),
                  ),
                  RowLight.takes => _Dashed(
                    color: c.goodLine,
                    fill: c.good.withValues(alpha: 0.14),
                  ),
                  RowLight.none => _Dashed(
                    color: c.emberLine,
                    fill: c.ember.withValues(alpha: 0.12),
                  ),
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 6,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 124),
                  child: Text(
                    vm.label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 12, color: c.text3),
                  ),
                ),
                Expanded(
                  child: Text(
                    vm.value,
                    maxLines: 1,
                    overflow: .ellipsis,
                    textAlign: .right,
                    style: mono(
                      size: 12,
                      color: switch (vm.tone) {
                        .plain => c.text1,
                        .bound => c.emberNew,
                        .bad => c.bad,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (vm.inMark != PortMark.none)
            Positioned(left: -5, top: 9, child: dot(vm.inMark)),
          if (vm.outMark != PortMark.none)
            Positioned(right: -5, top: 9, child: dot(vm.outMark)),
        ],
      ),
    );

    var child = row(light, point: vm.dropTarget);
    final inPort = vm.inPort;
    if (inPort != null) {
      // A point of the Tree tab dropped on an input (a palette Draggable).
      child = DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data.startsWith('key:'),
        onAcceptWithDetails: (d) => actions.onDropEntry(d.data, block, inPort),
        builder: (context, candidates, _) => candidates.isEmpty
            ? row(light, point: vm.dropTarget)
            : row(RowLight.none, point: true),
      );
    }
    final tip = vm.name.isEmpty || vm.name == vm.label ? '' : vm.name;
    return MouseRegion(
      cursor:
          vm.outPort != null ||
              vm.inMark == PortMark.bound ||
              vm.inMark == PortMark.write
          ? SystemMouseCursors.grab
          : MouseCursor.defer,
      child: tip.isEmpty
          ? child
          : Tooltip(
              message: tip,
              waitDuration: const Duration(milliseconds: 600),
              child: child,
            ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.tooltip, this.onTap});

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: Container(
          width: 28,
          height: 28,
          alignment: .center,
          decoration: BoxDecoration(
            border: .all(color: c.line2),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: onTap == null ? c.muted : c.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed box with a fill: where a dragged point lands.
class _Dashed extends CustomPainter {
  _Dashed({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(r, Paint()..color = fill);
    final p = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.fill != fill;
}
