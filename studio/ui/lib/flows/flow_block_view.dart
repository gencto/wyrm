import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/lines_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'block_palette.dart';
import 'field_word.dart';
import 'flow_intents.dart';

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

/// The colour of a field's value: plain, bound (the value that comes in
/// along its wire, accent), bad quality, stale (the draft no longer runs:
/// the last value of its preview, grey), ghost (what a sink would write in
/// a preview, nothing written).
enum ValueTone { plain, bound, bad, stale, ghost }

/// What a sink would do in the preview (nothing is written), said on the
/// row its value stands on: send its action, run it, or write its point.
enum GhostKindVm {
  send,
  run,
  write;

  /// The row's text: `would write 70.7`.
  String label(String value) => switch (this) {
    send => S.current.wouldSend(value),
    run => S.current.wouldRun(value),
    write => S.current.wouldWrite(value),
  };
}

/// The two blocks of the inside of a custom block: its inputs and its
/// outputs, titled in words.
enum BoundaryVm {
  inputs,
  outputs;

  String get label => switch (this) {
    inputs => S.current.blockInputs,
    outputs => S.current.blockOutputs,
  };
}

/// What − and + change: the ports of a boundary block, the pairs of
/// `case`/`router`, or the inputs of `add`, `if`, ….
enum VariadicKindVm {
  ports,
  pairs,
  inputs;

  /// `3 ports`, `2 cases`, `2 inputs`.
  String count(int n) => switch (this) {
    ports => S.current.portsCount(n),
    pairs => S.current.pairsCount(n),
    inputs => S.current.inputsCount(n),
  };

  String get add => switch (this) {
    ports => S.current.addPort,
    pairs => S.current.addPair,
    inputs => S.current.addInput,
  };

  String get remove => switch (this) {
    ports => S.current.removePort,
    pairs => S.current.removePair,
    inputs => S.current.removeInput,
  };
}

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
    this.word,
    this.name = '',
    this.value = '',
    this.tone = ValueTone.plain,
    this.inPort,
    this.outPort,
    this.inMark = PortMark.none,
    this.outMark = PortMark.none,
    this.dropTarget = false,
    this.outAliases = const [],
    this.editScope = false,
    this.command = false,
    this.ghost,
  });

  /// A command input (`date_range` `next`, `table_page` `first`): drawn
  /// as a button that a sample on its wire presses, with no value.
  final bool command;

  /// The `Scope` of a key: a pencil after the value opens its prompt.
  final bool editScope;

  /// Set on the row a sink's ghost stands on (the preview): [value] is what
  /// it would send or write.
  final GhostKindVm? ghost;

  /// The row's key within its block: what tells its widgets apart (the
  /// app's typed field id written out); never read back.
  final String id;

  /// The row's label when it is data: the engine's name made readable
  /// (`Input min`), a point's name; no colon. Empty when [word] says it.
  final String label;

  /// The row's label when it is Studio's own word (`Input 1`, `Output`).
  final FieldWordVm? word;

  /// What the row reads, in the language on screen.
  String get reads => word?.text ?? label;

  /// What the engine calls it (`input_min`, `in.0`): the row's tooltip.
  final String name;

  /// Already formatted (`92.6`, `4095`, `82.5 °C`).
  final String value;

  /// What the row shows: its value, or what its sink would do.
  String get shown => ghost?.label(value) ?? value;
  final ValueTone tone;

  /// The engine input a binding into it uses; null: no left port.
  final String? inPort;

  /// The engine output a binding out of it uses; null: no right port.
  final String? outPort;
  final PortMark inMark;
  final PortMark outMark;

  /// Lit as where a dragged point lands (dashed ember box).
  final bool dropTarget;

  /// Other engine outputs a wire may leave this field by (a variable's old
  /// `value` and `in` echoes); a new wire uses [outPort].
  final List<String> outAliases;

  /// Whether a wire out of [port] leaves this row.
  bool sends(String port) => port == outPort || outAliases.contains(port);

  @override
  List<Object?> get props => [
    id,
    label,
    word,
    name,
    value,
    tone,
    inPort,
    outPort,
    inMark,
    outMark,
    dropTarget,
    outAliases,
    editScope,
    ghost,
    command,
  ];
}

/// The − / + row of a block with variable inputs.
final class VariadicVm extends Equatable {
  const VariadicVm(
    this.kind, {
    required this.count,
    this.canRemove = true,
    this.canAdd = true,
  });

  final VariadicKindVm kind;

  /// How many ports, pairs or inputs there are.
  final int count;
  final bool canRemove;
  final bool canAdd;

  /// `2 inputs`, `3 cases`.
  String get label => kind.count(count);

  @override
  List<Object?> get props => [kind, count, canRemove, canAdd];
}

/// One block on the canvas.
final class FlowBlockVm extends Equatable {
  const FlowBlockVm({
    required this.id,
    required this.x,
    required this.y,
    this.title,
    this.boundary,
    this.caption = const [],
    this.kind = BlockKindVm.logic,
    this.width = AppSizes.flowBlockWidth,
    this.rows = const [],
    this.variadic,
    this.selected = false,
    this.preview = false,
    this.openable = false,
  });

  final String id;

  /// The inputs or outputs block of a custom block's inside; null: a block
  /// of the flow, titled by its id.
  final BoundaryVm? boundary;

  /// A link row under the fields, `Open inside`: the inside of a custom
  /// block's instance.
  final bool openable;

  /// A `preview` chip in the header after the title: a sink's value is what
  /// it would write.
  final bool preview;

  /// What it is, in parts (`tcp-tank`, `ramp`): the type (`scale`), the
  /// connection of a tree point (`modbus/tcp-tank`), an action block's node
  /// and action.
  final List<String> caption;

  /// What the header names it, when not its id (the app titles a block by
  /// its id).
  final String? title;

  /// The header's title, mono: the boundary's name, else [title], else the
  /// id.
  String get heading => boundary?.label ?? title ?? id;

  /// On the right of the header: [caption] read as one.
  String get type => caption.join(' · ');
  final BlockKindVm kind;
  final double x;
  final double y;

  /// 200–220 (spec §3).
  final double width;
  final List<FieldRowVm> rows;
  final VariadicVm? variadic;
  final bool selected;

  FlowBlockVm at(double x, double y) => _with(x: x, y: y);

  /// The same block drawn selected or not (a marquee in progress).
  FlowBlockVm marked({required bool selected}) => _with(selected: selected);

  FlowBlockVm _with({double? x, double? y, bool? selected}) => FlowBlockVm(
    id: id,
    title: title,
    boundary: boundary,
    x: x ?? this.x,
    y: y ?? this.y,
    caption: caption,
    kind: kind,
    width: width,
    rows: rows,
    variadic: variadic,
    selected: selected ?? this.selected,
    preview: preview,
    openable: openable,
  );

  /// The block's box on the canvas.
  Rect get rect => Rect.fromLTWH(x, y, width, height);

  static const double headerHeight = AppSizes.flowBlockHeader;
  static const double rowHeight = AppSizes.flowBlockRow;
  static const double bodyTop = AppSizes.flowBlockBodyTop;

  /// The − / + row under the fields.
  static const double toolsHeight = AppSizes.flowBlockTools;

  /// How tall the block is drawn: header, body padding 6 + 8, 28 per row
  /// (at least one), the − / + row.
  double get height =>
      headerHeight +
      bodyTop +
      rowHeight * (rows.isEmpty ? 1 : rows.length) +
      (openable ? rowHeight : 0) +
      AppSpacing.sm +
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
      (r) => output ? r.sends(port) : r.inPort == port,
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
    boundary,
    caption,
    kind,
    x,
    y,
    width,
    rows,
    variadic,
    selected,
    preview,
    openable,
  ];
}

/// How a row is lit: while a wire is dragged over it (takes, refuses), or
/// as the source of the bound field under the pointer (source).
enum RowLight { none, takes, refuses, source }

/// A block of the flow editor (spec §3): a header with its kind chip, mono
/// title and type, then one row per field with its value and ports. The
/// canvas moves it and draws wires from and into its rows; a row with an
/// input takes a point dropped from the Tree tab. [lit] is the row a
/// dragged wire is over, [light] how it is lit.
class FlowBlockView extends StatelessWidget {
  const FlowBlockView({
    required this.vm,
    this.onOpen,
    this.onResize,
    this.onView,
    this.onRowAction,
    this.lit,
    this.light = RowLight.none,
    super.key,
  });

  final FlowBlockVm vm;

  /// The `Open inside` row ([FlowBlockVm.openable]).
  final VoidCallback? onOpen;

  /// − or + of the variable inputs.
  final ValueChanged<BlockResized>? onResize;

  /// The mark of a value of several lines (`↲ +1`) on a row: opens the
  /// row's value in the viewer.
  final ValueChanged<RowRef>? onView;

  /// The pencil of a row ([FieldRowVm.editScope]).
  final ValueChanged<RowRef>? onRowAction;
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
      .my => (FixedGrounds.flowOwnBlockHeader, c.emberSoft),
    };
    return Container(
      width: vm.width,
      decoration: BoxDecoration(
        color: c.ground2,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.control)),
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
              padding: Insets.control,
              decoration: BoxDecoration(
                color: headerFill,
                borderRadius: Radii.flowBlockHeader,
              ),
              child: Row(
                spacing: AppSpacing.sm,
                children: [
                  Container(
                    padding: Insets.flowBlockChip,
                    decoration: BoxDecoration(
                      border: .all(color: ink),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadii.mark),
                      ),
                    ),
                    child: Text(
                      vm.kind.chip,
                      style: mono(
                        size: FontSizes.flowTag,
                        weight: .w600,
                        color: ink,
                      ).copyWith(height: 1.2),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: vm.width * 0.55),
                    child: Text(
                      vm.heading,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: mono(weight: .w600, color: c.text1),
                    ),
                  ),
                  if (vm.preview)
                    Container(
                      padding: Insets.flowBlockChip,
                      decoration: BoxDecoration(
                        color: c.emberTint,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadii.mark),
                        ),
                      ),
                      child: Text(
                        S.current.previewTag,
                        style: mono(
                          size: FontSizes.flowTag,
                          color: c.emberSoft,
                        ).copyWith(height: 1.2),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      vm.type,
                      maxLines: 1,
                      overflow: .ellipsis,
                      textAlign: .right,
                      style: mono(size: FontSizes.xs, color: c.text4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: FlowBlockVm.bodyTop,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (vm.rows.isEmpty)
                  const SizedBox(height: FlowBlockVm.rowHeight),
                for (final (i, r) in vm.rows.indexed)
                  _FieldRow(
                    block: vm.id,
                    vm: r,
                    at: RowRef(vm.id, i),
                    onView: onView,
                    onAction: onRowAction,
                    light: r.id == lit ? light : RowLight.none,
                  ),
                if (vm.openable)
                  InkWell(
                    key: ValueKey('open-${vm.id}'),
                    onTap: onOpen,
                    child: SizedBox(
                      height: FlowBlockVm.rowHeight,
                      child: Padding(
                        padding: Insets.flowBlockRow,
                        child: Row(
                          spacing: AppSpacing.flowRowParts,
                          children: [
                            Expanded(
                              child: Text(
                                S.current.openInside,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  fontSize: FontSizes.sm,
                                  color: c.emberSoft,
                                ),
                              ),
                            ),
                            AppIcon(
                              'ui_chevron_right',
                              size: AppSizes.flowLinkChevron,
                              color: c.emberSoft,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (vm.variadic case final v?)
                  Container(
                    margin: Insets.flowBlockToolsMargin,
                    padding: Insets.flowBlockTools,
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line1)),
                    ),
                    child: Row(
                      spacing: AppSpacing.flowRowParts,
                      children: [
                        _ToolButton(
                          label: '−',
                          tooltip: v.kind.remove,
                          onTap: v.canRemove && onResize != null
                              ? () => onResize!(BlockResized(vm.id, add: false))
                              : null,
                        ),
                        _ToolButton(
                          label: '+',
                          tooltip: v.kind.add,
                          onTap: v.canAdd && onResize != null
                              ? () => onResize!(BlockResized(vm.id, add: true))
                              : null,
                        ),
                        Text(
                          v.label,
                          style: TextStyle(
                            fontSize: FontSizes.sm,
                            color: c.text4,
                          ),
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
    required this.at,
    required this.light,
    this.onView,
    this.onAction,
  });

  final String block;
  final FieldRowVm vm;

  /// Where the row stands: what it reports.
  final RowRef at;
  final ValueChanged<RowRef>? onView;
  final ValueChanged<RowRef>? onAction;
  final RowLight light;

  /// A port stands half out of the block, on its row's centre line.
  static const double _portInset = AppSizes.flowPort / 2;
  static const double _portTop =
      (AppSizes.flowBlockRow - AppSizes.flowPort) / 2;

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
        width: AppSizes.flowPort,
        height: AppSizes.flowPort,
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
                  RowLight.source => _Dashed(
                    color: c.good,
                    fill: c.good.withValues(alpha: 0.10),
                    solid: true,
                  ),
                  RowLight.none => _Dashed(
                    color: c.emberLine,
                    fill: c.ember.withValues(alpha: 0.12),
                  ),
                },
              ),
            ),
          // Fills the row, so the text sits on the row's centre line, where
          // the ports are.
          Positioned.fill(
            child: Padding(
              padding: Insets.flowBlockRow,
              child: Row(
                spacing: AppSpacing.flowRowParts,
                children: [
                  if (vm.command)
                    Container(
                      key: ValueKey('command-$block-${vm.id}'),
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.flowCommandMaxWidth,
                      ),
                      padding: Insets.flowBlockCommand,
                      decoration: BoxDecoration(
                        color: c.ground3,
                        border: .all(color: c.line2),
                        borderRadius: Radii.flowCommand,
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        spacing: AppSpacing.xs,
                        children: [
                          AppIcon(
                            'action_play',
                            size: AppSizes.flowCommandIcon,
                            color: c.text3,
                          ),
                          Flexible(
                            child: Text(
                              vm.reads,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: TextStyle(
                                fontSize: FontSizes.xs,
                                color: c.text2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.flowRowLabelMaxWidth,
                      ),
                      child: Text(
                        vm.reads,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: c.text3,
                        ),
                      ),
                    ),
                  Expanded(
                    // A text of several lines shows its first and a mark
                    // with how many more (owner's finding 2026-11-11).
                    child: LinesText(
                      vm.shown,
                      textAlign: .right,
                      onOpen: onView == null ? null : () => onView!(at),
                      style: mono(
                        size: FontSizes.sm,
                        color: switch (vm.tone) {
                          .plain => c.text1,
                          .bound => c.emberNew,
                          .bad => c.bad,
                          .stale => c.muted,
                          .ghost => c.emberSoft.withValues(alpha: 0.75),
                        },
                      ).copyWith(fontStyle: vm.tone == .ghost ? .italic : null),
                    ),
                  ),
                  if (vm.editScope)
                    Tooltip(
                      message: S.current.scopeEdit,
                      child: InkWell(
                        key: ValueKey('row-action-$block-${vm.id}'),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadii.chip),
                        ),
                        onTap: onAction == null ? null : () => onAction!(at),
                        child: Padding(
                          padding: Insets.flowBlockRowAction,
                          child: AppIcon(
                            'action_edit',
                            size: AppSizes.flowRowActionIcon,
                            color: c.text3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (vm.inMark != PortMark.none)
            Positioned(left: -_portInset, top: _portTop, child: dot(vm.inMark)),
          if (vm.outMark != PortMark.none)
            Positioned(
              right: -_portInset,
              top: _portTop,
              child: dot(vm.outMark),
            ),
        ],
      ),
    );

    var child = row(light, point: vm.dropTarget);
    final inPort = vm.inPort;
    if (inPort != null) {
      // A point of the Tree tab dropped on an input (a palette Draggable).
      child = DragTarget<PaletteDrag>(
        onWillAcceptWithDetails: (d) => d.data.point,
        onAcceptWithDetails: (d) => d.data.place(PlaceOnInput(block, inPort)),
        builder: (context, candidates, _) => candidates.isEmpty
            ? row(light, point: vm.dropTarget)
            : row(RowLight.none, point: true),
      );
    }
    final tip = vm.name.isEmpty || vm.name == vm.reads ? '' : vm.name;
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
              waitDuration: Motion.flowFieldTipWait,
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
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.segment)),
        child: Container(
          width: AppSizes.flowToolButton,
          height: AppSizes.flowToolButton,
          alignment: .center,
          decoration: BoxDecoration(
            border: .all(color: c.line2),
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.segment),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: FontSizes.flowToolGlyph,
              color: onTap == null ? c.muted : c.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed box with a fill: where a dragged point lands; [solid] draws
/// the border whole (the source of a hovered binding).
class _Dashed extends CustomPainter {
  _Dashed({required this.color, required this.fill, this.solid = false});

  final Color color;
  final Color fill;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadii.chip),
    );
    canvas.drawRRect(r, Paint()..color = fill);
    final p = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(r);
    if (solid) {
      canvas.drawPath(path, p);
      return;
    }
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) =>
      old.color != color || old.fill != fill || old.solid != solid;
}
