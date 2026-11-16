import 'dart:async';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../models/query.dart';
import '../models/value_changed.dart';
import '../overlays/floating_window.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'bind_refusal.dart';
import 'block_palette.dart';
import 'field_drop_zone.dart';
import 'flow_block_view.dart';
import 'flow_intents.dart';
import 'flow_legend.dart';
import 'flow_menu.dart';
import 'scope_prompt.dart';
import 'shortcut_card.dart';

/// One wire: output `<from>.<fromPort>` → input `<to>.<toPort>`.
final class FlowWireVm extends Equatable {
  const FlowWireVm(
    this.from,
    this.fromPort,
    this.to,
    this.toPort, {
    this.writes = false,
    this.firesAtDeploy = false,
  });

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  /// It writes to a device (into a writable point, a `set` or an `invoke`):
  /// ember; everything else reads a value: teal.
  final bool writes;

  /// A `fires at deploy` chip on the wire: a parameter's echo into a device
  /// sends at start (ADR 0038 §6); its tooltip says so.
  final bool firesAtDeploy;

  @override
  List<Object?> get props => [
    from,
    fromPort,
    to,
    toPort,
    writes,
    firesAtDeploy,
  ];
}

/// The canvas of the flow editor (spec §3–§5, §12–§14): blocks on a dot
/// grid, S-curve wires from a field's right port to another's left port,
/// the legend and the `?` button pinned bottom-left.
///
/// The canvas reads the pointer itself, in its own coordinates, so what is
/// dragged stays under the pointer at any zoom and scroll:
/// - a block's header moves the block, and with it the whole selection
///   when the block is part of one (snapped to the 20 px grid when let go);
/// - a drag on the empty canvas draws a marquee: the blocks it touches are
///   selected (Shift adds them, ⌘/Ctrl switches them); a click there
///   clears the selection; Shift- or ⌘/Ctrl-click on a block switches it
///   in or out of the selection;
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
/// - Space + drag, the middle button, the wheel and two fingers on a
///   trackpad pan; ⌘/Ctrl + wheel and a pinch zoom about the pointer;
/// - the right button opens the context menu ([FlowMenu]) of the block,
///   of the selection or of the canvas.
///
/// Every key comes from [flowShortcuts]; the canvas takes keys while
/// its route is on top and no text field or floating window has the
/// focus. What changes the flow goes out as a [FlowCommand] ([onCommand]);
/// zoom, the shortcut card and the selection by keys are the canvas's own.
///
/// A wire let go outside the canvas over a [FieldDropZone] (the inspector)
/// binds that field. A palette entry dropped on the canvas places a block
/// with the pointer on its header.
class FlowCanvas extends StatefulWidget {
  const FlowCanvas({
    required this.blocks,
    required this.wires,
    required this.onSelect,
    required this.onBind,
    required this.onRebind,
    required this.onUnbind,
    required this.onClear,
    required this.onMove,
    this.onResize,
    this.refusal,
    this.onOpen,
    this.onRowAction,
    this.onSelectMany,
    this.onCommand,
    this.menu,
    this.onViewField,
    this.legend = false,
    this.controller,
    this.help = false,
    this.mac,
    this.view,
    this.prompt,
    this.onPromptSave,
    this.onPromptCancel,
    this.validatePrompt,
    super.key,
  });

  /// The scope asked of a key that got a wire ([ScopePrompt]): drawn on
  /// that field's row.
  final ScopePromptVm? prompt;
  final ValueChanged<String>? onPromptSave;
  final VoidCallback? onPromptCancel;
  final Validate<String>? validatePrompt;

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;

  /// A block clicked (or picked up): selected alone.
  final ValueChanged<String> onSelect;

  /// A wire let go on an input that takes it.
  final ValueChanged<WireDropped> onBind;

  /// A picked-up wire let go on another input.
  final ValueChanged<WireMoved> onRebind;

  /// Double click or Alt-click on a bound input, or its wire picked up and
  /// let go on the empty canvas.
  final ValueChanged<RowRef> onUnbind;

  /// − or + of a block's variable inputs.
  final ValueChanged<BlockResized>? onResize;

  /// Why a row does not take the wire dragged over it; null: it does.
  final QueryVm<BindAsk, BindRefusalVm?>? refusal;

  /// `Open inside` of a custom block's instance (its id).
  final ValueChanged<String>? onOpen;

  /// The pencil of a row (the scope of a key).
  final ValueChanged<RowRef>? onRowAction;

  /// A click on the empty canvas.
  final VoidCallback onClear;

  /// Blocks let go at their new top-left corners, on the grid.
  final ValueChanged<BlocksMoved> onMove;

  /// A marquee or Select all.
  final ValueChanged<BlocksSelected>? onSelectMany;

  /// A command the canvas does not do by itself (copy, paste, delete,
  /// undo, deploy, …), from a key or from the context menu.
  final ValueChanged<CanvasCommand>? onCommand;

  /// The context menu for a right click: on a block (and its row) with
  /// the selection's ids, or on the empty canvas (both null). Its fields
  /// pin and unpin themselves ([FlowPinVm.onPin]).
  final QueryVm<FlowMenuAsk, FlowMenuVm>? menu;

  /// `V` over a row, or the mark of a value of several lines: opens its
  /// value in the viewer.
  final ValueChanged<RowRef>? onViewField;

  /// The legend of the wires and ports, bottom-left.
  final bool legend;

  /// The zoom and scroll; the canvas keeps its own when none is given.
  final TransformationController? controller;

  /// Whether the shortcut card is open at first.
  final bool help;

  /// ⌘ glyphs in the card and the menu; null: this machine's.
  final bool? mac;

  /// What the canvas shows (the flow's id, and the block opened inside
  /// it): when it changes and its blocks do not all show, the view fits
  /// them (spec §25). Null: never fitted by itself.
  final String? view;

  /// The smallest canvas: an empty or small flow still has room to grow.
  static const size = Size(3000, 2000);

  /// Room past the last block to the right and below it, so it can be
  /// panned clear of the legend and moved further out.
  static const margin = 400.0;

  /// The canvas for [blocks]: every block with [margin] past it, never
  /// smaller than [size]. Panning, moving and dropping reach all of it.
  static Size extentOf(Iterable<FlowBlockVm> blocks) {
    var w = size.width;
    var h = size.height;
    for (final b in blocks) {
      w = math.max(w, b.x + b.width + margin);
      h = math.max(h, b.y + b.height + margin);
    }
    return Size(w, h);
  }

  /// The grid blocks snap to.
  static const grid = 20.0;

  /// How far Shift + an arrow moves the selection, in grid steps.
  static const farNudge = 10;

  /// Where a dropped block's top-left goes relative to the pointer: the
  /// pointer lands on the header, past the kind chip.
  static const dropGrab = Offset(24, 16);

  /// How far the pointer moves, on the screen, before a press drags.
  static const slop = 3.0;

  static const minScale = 0.25;
  static const maxScale = 2.0;

  /// One step of ⌘/Ctrl + and −.
  static const zoomStep = 1.2;

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

/// A rectangle drawn on the empty canvas.
final class _Marquee extends _Press {
  _Marquee(
    super.down,
    this.from, {
    required this.add,
    required this.toggle,
    required this.base,
  }) : to = from;

  /// Its corners, in canvas coordinates.
  final Offset from;
  Offset to;

  /// Shift: what it touches joins the selection.
  final bool add;

  /// ⌘/Ctrl: what it touches switches in or out of it.
  final bool toggle;

  /// What was selected when it began.
  final Set<String> base;
  var hit = <String>{};

  Rect get rect => Rect.fromPoints(from, to);

  /// Whether [id] reads selected while the marquee is drawn.
  bool selects(String id) => toggle
      ? base.contains(id) != hit.contains(id)
      : (add && base.contains(id)) || hit.contains(id);
}

final class _Move extends _Press {
  _Move(
    super.down,
    this.anchor,
    this.grab,
    this.origins, {
    required this.narrow,
  });

  /// The block under the pointer.
  final String anchor;

  /// The pointer's place on [anchor], kept while it moves.
  final Offset grab;

  /// Where every moving block was.
  final Map<String, Offset> origins;

  /// A click without a drag selects [anchor] alone (it was one of several).
  final bool narrow;
  var at = <String, Offset>{};
}

/// A row of a block as the canvas holds it while the pointer works: the
/// block, the row's place among its rows and its key (what draws it lit).
final class _Spot {
  const _Spot(this.block, this.index, this.key);

  final String block;
  final int index;
  final String key;

  RowRef get ref => RowRef(block, index);

  @override
  bool operator ==(Object other) =>
      other is _Spot && other.block == block && other.key == key;

  @override
  int get hashCode => Object.hash(block, key);
}

/// The input a picked-up wire leaves: its end and its row.
final class _Picked {
  const _Picked(this.end, this.spot);

  final PortRefVm end;
  final _Spot spot;
}

final class _Wire extends _Press {
  _Wire(super.down, this.from, {this.picked});

  /// The output the wire comes from.
  final FieldRefVm from;

  /// The input a picked-up wire leaves.
  final _Picked? picked;
  Offset pointer = Offset.zero;

  /// The row under the pointer; with [refusal] when it refuses.
  _Spot? over;
  BindRefusalVm? refusal;

  /// The field outside the canvas under the pointer.
  FieldDrop? outside;
}

/// A press that only selects (a field with nothing to drag, the body).
final class _Tap extends _Press {
  _Tap(super.down, [this.spot]);

  /// The row pressed; null: the block's body.
  final _Spot? spot;
}

class _FlowCanvasState extends State<FlowCanvas> {
  final GlobalKey<State<StatefulWidget>> _key = GlobalKey();
  final GlobalKey<State<StatefulWidget>> _view = GlobalKey();
  TransformationController? _own;
  _Press? _press;
  ModalRoute<Object?>? _route;

  /// The last click on a row, for a double click: the row, and when.
  _Spot? _lastClick;
  Duration _lastClickAt = Duration.zero;

  /// The bound field under the pointer.
  _Spot? _hover;

  /// Where the mouse was last, on the screen: where a paste lands.
  Offset? _pointer;

  /// Space is held: a drag pans.
  var _space = false;

  /// The pinch so far of a trackpad gesture.
  var _pinch = 1.0;

  /// The shortcut card is open.
  late bool _help = widget.help;

  /// Fit every block into the view when the blocks next change (after
  /// Tidy up).
  var _fitNext = false;

  /// The last [FlowCanvas.view] shown with its blocks: fitted once.
  String? _opened;

  /// The legend and the tools along the bottom: a fit leaves them room.
  final GlobalKey<State<StatefulWidget>> _bar = GlobalKey();

  TransformationController get _ctl =>
      widget.controller ?? (_own ??= TransformationController());

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _fitLater();
  }

  @override
  void didUpdateWidget(FlowCanvas old) {
    super.didUpdateWidget(old);
    _fitLater();
  }

  /// After this frame (when the view has its size): a flow just opened
  /// whose blocks do not all show is fitted to the view (spec §25); after
  /// Tidy up every flow is.
  void _fitLater() {
    final view = widget.view;
    final opened = view != null && view != _opened && widget.blocks.isNotEmpty;
    final tidied = _fitNext && !identical(widget.blocks, _tidiedFrom);
    if (!opened && !tidied) {
      return;
    }
    if (opened) {
      _opened = view;
    }
    if (tidied) {
      _fitNext = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (tidied || !_allShown())) {
        _fit();
      }
    });
  }

  /// The blocks when Tidy up was asked: the next ones are its result.
  List<FlowBlockVm>? _tidiedFrom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _own?.dispose();
    super.dispose();
  }

  // ---------- what is drawn ----------

  /// The blocks' widgets as last built, by id.
  final _built = <String, _BuiltBlock>{};

  /// The widget of block [b]: the one built before while its render model
  /// is the same object and it is lit the same, so Flutter leaves a block
  /// that did not change as it is. Its callbacks call this canvas's own
  /// when they run.
  Widget _block(
    FlowBlockVm b, {
    required String? lit,
    required RowLight light,
  }) {
    final old = _built[b.id];
    final reacts = (
      widget.onOpen != null,
      widget.onResize != null,
      widget.onViewField != null,
      widget.onRowAction != null,
    );
    if (old != null &&
        identical(old.vm, b) &&
        old.lit == lit &&
        old.light == light &&
        old.reacts == reacts) {
      return old.widget;
    }
    final built = FlowBlockView(
      key: ValueKey(b.id),
      vm: b,
      onOpen: widget.onOpen == null ? null : () => widget.onOpen?.call(b.id),
      onResize: widget.onResize == null
          ? null
          : (r) => widget.onResize?.call(r),
      onView: widget.onViewField == null
          ? null
          : (r) => widget.onViewField?.call(r),
      onRowAction: widget.onRowAction == null
          ? null
          : (r) => widget.onRowAction?.call(r),
      lit: lit,
      light: light,
    );
    _built[b.id] = _BuiltBlock(b, lit, light, reacts, built);
    return built;
  }

  /// The blocks as drawn: the moving ones where the pointer has them, and
  /// under a marquee the selection it would give.
  List<FlowBlockVm> get _blocks {
    final press = _press;
    return [
      for (final b in widget.blocks)
        switch (press) {
          _Move(:final at) when at[b.id] != null => b.at(
            at[b.id]!.dx,
            at[b.id]!.dy,
          ),
          _Marquee(dragging: true) when press.selects(b.id) != b.selected =>
            b.marked(selected: press.selects(b.id)),
          _ => b,
        },
    ];
  }

  Set<String> get _selected => {
    for (final b in widget.blocks)
      if (b.selected) b.id,
  };

  // ---------- coordinates, zoom and scroll ----------

  /// [global] in canvas coordinates (through the zoom and the scroll).
  Offset _local(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  RenderBox? get _viewBox =>
      _view.currentContext?.findRenderObject() as RenderBox?;

  bool _inView(Offset global) {
    final box = _viewBox;
    if (box == null) {
      return true;
    }
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  /// The zoom: the x scale of the transform. (`getMaxScaleOnAxis` also
  /// counts the z axis, which stays 1: it never reads below 100 %.)
  double get _scale => _ctl.value.entry(0, 0);

  Offset get _shift {
    final t = _ctl.value.getTranslation();
    return Offset(t.x, t.y);
  }

  /// Shows the canvas at [scale], its origin at [shift] in the view; both
  /// kept in bounds: the zoom in [FlowCanvas.minScale] …
  /// [FlowCanvas.maxScale], the canvas never more than 200 px away from the
  /// view's edges.
  void _setView(double scale, Offset shift) {
    final s = scale.clamp(FlowCanvas.minScale, FlowCanvas.maxScale);
    final view = _viewBox?.size ?? Size.zero;
    final extent = FlowCanvas.extentOf(widget.blocks);
    double bound(double v, double viewLength, double length) {
      final low = math.min<double>(200, viewLength - length * s - 200);
      return v.clamp(low, 200.0);
    }

    _ctl.value = Matrix4.identity()
      ..translateByDouble(
        bound(shift.dx, view.width, extent.width),
        bound(shift.dy, view.height, extent.height),
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
  }

  void _panBy(Offset delta) => _setView(_scale, _shift + delta);

  /// Zooms to [scale] so that the canvas point under [focal] (in the
  /// view; its centre when null) stays there.
  void _zoomTo(double scale, {Offset? focal}) {
    final box = _viewBox;
    final f = focal ?? (box == null ? Offset.zero : box.size.center(.zero));
    final s = scale.clamp(FlowCanvas.minScale, FlowCanvas.maxScale);
    final at = (f - _shift) / _scale;
    _setView(s, f - at * s);
  }

  Offset? _viewPoint(Offset global) => _viewBox?.globalToLocal(global);

  /// The part of the view the blocks may use: all of it but the legend
  /// and the tools along the bottom.
  Rect? get _room {
    final box = _viewBox;
    if (box == null) {
      return null;
    }
    final bar = _bar.currentContext?.size?.height ?? 0;
    return Offset.zero &
        Size(box.size.width, math.max(1, box.size.height - bar - 16));
  }

  /// Whether every block shows whole in [_room] now.
  bool _allShown() {
    final room = _room;
    if (room == null) {
      return true;
    }
    return widget.blocks.every(
      (b) =>
          room.contains(
            MatrixUtils.transformPoint(_ctl.value, b.rect.topLeft),
          ) &&
          room.contains(
            MatrixUtils.transformPoint(_ctl.value, b.rect.bottomRight),
          ),
    );
  }

  /// Shows every block above the legend, at 100 % at most. A flow too
  /// large even at the smallest zoom shows from its top-left corner.
  void _fit() {
    final room = _room;
    if (widget.blocks.isEmpty || room == null) {
      _zoomTo(1);
      return;
    }
    final all = widget.blocks
        .map((b) => b.rect)
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(40);
    final s = math
        .min(room.width / all.width, room.height / all.height)
        .clamp(FlowCanvas.minScale, 1.0);
    double place(double roomLength, double start, double length) =>
        length * s <= roomLength
        ? (roomLength - length * s) / 2 - start * s
        : -start * s;
    _setView(
      s,
      Offset(
        place(room.width, all.left, all.width),
        place(room.height, all.top, all.height),
      ),
    );
  }

  // ---------- keys ----------

  /// Whether the canvas takes keys now: its route is on top, and neither a
  /// text field nor a floating window (the value viewer) has the focus.
  bool get _keysOn {
    if (!mounted || !(_route?.isCurrent ?? true)) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) {
      return true;
    }
    return focus.widget is! EditableText &&
        focus.findAncestorWidgetOfExactType<EditableText>() == null &&
        focus.findAncestorWidgetOfExactType<FloatingWindow>() == null;
  }

  static const Set<FlowCommand> _repeating = {
    FlowCommand.nudgeLeft,
    FlowCommand.nudgeRight,
    FlowCommand.nudgeUp,
    FlowCommand.nudgeDown,
    FlowCommand.zoomIn,
    FlowCommand.zoomOut,
    FlowCommand.undo,
    FlowCommand.redo,
  };

  bool _onKey(KeyEvent e) {
    if (!mounted) {
      return false;
    }
    if (e.logicalKey == LogicalKeyboardKey.space) {
      final held = e is! KeyUpEvent && _keysOn;
      if (held != _space) {
        setState(() => _space = held);
      }
      return false;
    }
    if (e is KeyUpEvent || !_keysOn) {
      return false;
    }
    final command = flowCommandOf(e.logicalKey);
    if (command == null) {
      return false;
    }
    if (e is! KeyRepeatEvent || _repeating.contains(command)) {
      _run(command);
    }
    return true;
  }

  /// Does [command]: the canvas's own ones here, the rest through
  /// [FlowCanvas.onCommand]. [at] is where the menu was opened (canvas
  /// coordinates): where a paste lands.
  void _run(FlowCommand command, {Offset? at}) {
    switch (command) {
      case .help:
        setState(() => _help = !_help);
      case .escape:
        if (_help) {
          setState(() => _help = false);
        } else if (_press != null) {
          _cancel();
        } else {
          widget.onCommand?.call(const CanvasCommand(.escape));
        }
      case .selectAll:
        widget.onSelectMany?.call(
          BlocksSelected(
            {for (final b in widget.blocks) b.id},
            add: false,
            toggle: false,
          ),
        );
      case .nudgeLeft:
        _nudge(-1, 0);
      case .nudgeRight:
        _nudge(1, 0);
      case .nudgeUp:
        _nudge(0, -1);
      case .nudgeDown:
        _nudge(0, 1);
      case .zoomIn:
        _zoomTo(_scale * FlowCanvas.zoomStep);
      case .zoomOut:
        _zoomTo(_scale / FlowCanvas.zoomStep);
      case .zoomReset:
        _zoomTo(1);
      case .zoomFit:
        _fit();
      case .viewValue:
        final p = _pointer;
        final b = p == null ? null : _blockAt(_blocks, _local(p));
        final i = p == null ? null : b?.rowAt(_local(p));
        if (b != null && i != null) {
          widget.onViewField?.call(RowRef(b.id, i));
        }
      case .paste:
        widget.onCommand?.call(CanvasCommand(.paste, at: at ?? _pasteAt()));
      case .copy ||
          .cut ||
          .duplicate ||
          .delete ||
          .undo ||
          .redo ||
          .searchPalette ||
          .deploy ||
          .createCustomBlock ||
          .editCustomBlock:
        widget.onCommand?.call(CanvasCommand(command));
      case .tidy:
        // The blocks move: show them all once they have.
        _fitNext = true;
        _tidiedFrom = widget.blocks;
        widget.onCommand?.call(CanvasCommand(command));
      // Gestures of the pointer and the menu's own entries: not keys.
      case .marquee ||
          .addToSelection ||
          .moveSelection ||
          .unbind ||
          .pan ||
          .zoom ||
          .fields ||
          .unpin:
        break;
    }
  }

  /// Where a paste by the keyboard lands: under the mouse when it is over
  /// the canvas, else in the middle of the view.
  Offset _pasteAt() {
    final p = _pointer;
    if (p != null && _inView(p)) {
      return _local(p);
    }
    final box = _viewBox;
    return box == null
        ? const Offset(60, 60)
        : _local(box.localToGlobal(box.size.center(.zero)));
  }

  /// Moves the selection one grid step (ten with Shift), inside the canvas.
  void _nudge(int dx, int dy) {
    final moving = [
      for (final b in widget.blocks)
        if (b.selected) b,
    ];
    if (moving.isEmpty) {
      return;
    }
    final far = HardwareKeyboard.instance.isShiftPressed;
    final step = FlowCanvas.grid * (far ? FlowCanvas.farNudge : 1);
    final delta = _inside(moving, Offset(dx * step, dy * step));
    widget.onMove(
      BlocksMoved({
        for (final b in moving)
          b.id: Offset(
            FlowCanvas.snap(b.x + delta.dx),
            FlowCanvas.snap(b.y + delta.dy),
          ),
      }, nudge: true),
    );
  }

  /// [delta] shortened so that every block of [moving] stays on the canvas.
  Offset _inside(List<FlowBlockVm> moving, Offset delta) {
    final extent = FlowCanvas.extentOf(widget.blocks);
    final box = moving
        .map((b) => b.rect)
        .reduce((a, b) => a.expandToInclude(b));
    return Offset(
      delta.dx.clamp(
        -box.left,
        math.max(-box.left, extent.width - box.right),
      ),
      delta.dy.clamp(
        -box.top,
        math.max(-box.top, extent.height - box.bottom),
      ),
    );
  }

  // ---------- the pointer ----------

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
    _pointer = e.position;
    final p = _local(e.position);
    final b = _blockAt(_blocks, p);
    final i = b?.rowAt(p);
    final next = b != null && i != null && _bound(b.rows[i])
        ? _Spot(b.id, i, b.rows[i].id)
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
    final port = byId[h.block]?.rows
        .where((r) => r.id == h.key)
        .firstOrNull
        ?.inPort;
    return widget.wires
        .where((w) => w.to == h.block && w.toPort == port)
        .firstOrNull;
  }

  void _cancel() => setState(() {
    _press = null;
    fieldDropHover.value = null;
  });

  void _down(PointerDownEvent e) {
    _pointer = e.position;
    // The canvas takes the keys: a text field elsewhere lets go.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_help) {
      return;
    }
    final p = _local(e.position);
    if (e.buttons == kSecondaryMouseButton) {
      unawaited(_openMenu(e.position, p));
      return;
    }
    if (e.buttons == kMiddleMouseButton ||
        (e.buttons == kPrimaryButton && _space)) {
      _press = _Pan(e.position);
      return;
    }
    if (e.buttons != kPrimaryButton) {
      return;
    }
    final blocks = _blocks;
    final b = _blockAt(blocks, p);
    if (b == null) {
      _press = _Marquee(
        e.position,
        p,
        add: flowGestureHeld(.addToSelection, .dragEmpty),
        toggle: flowPrimaryHeld(),
        base: _selected,
      );
      return;
    }
    if (flowGestureHeld(.addToSelection, .click)) {
      widget.onSelectMany?.call(
        BlocksSelected({b.id}, add: false, toggle: true),
      );
      return;
    }
    final many = b.selected && _selected.length > 1;
    if (!b.selected) {
      widget.onSelect(b.id);
    }
    if (b.onHeader(p)) {
      _press = _Move(
        e.position,
        b.id,
        p - Offset(b.x, b.y),
        {
          for (final x in blocks)
            if (x.id == b.id || (many && x.selected)) x.id: Offset(x.x, x.y),
        },
        narrow: many,
      );
      return;
    }
    final i = b.rowAt(p);
    if (i == null) {
      _press = _Tap(e.position);
      return;
    }
    final r = b.rows[i];
    if (_bound(r) && flowGestureHeld(.unbind, .click)) {
      _press = null;
      widget.onUnbind(RowRef(b.id, i));
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
          picked: _Picked(PortRefVm(b.id, r.inPort!), _Spot(b.id, i, r.id)),
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
    _press = _Tap(e.position, _Spot(b.id, i, r.id));
  }

  /// A writable point let go at [global]: `Read` or `Write` where it
  /// landed (true: write); Alt held writes at once; null: neither picked.
  Future<bool?> _readOrWrite(Offset global) async {
    if (HardwareKeyboard.instance.isAltPressed) {
      return true;
    }
    final c = context.colors;
    return showMenu<bool>(
      context: context,
      color: c.ground3,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        for (final write in const [false, true])
          PopupMenuItem(
            value: write,
            height: AppSizes.flowMenuItem,
            child: Text(
              write ? S.current.dropWrite : S.current.dropRead,
              style: TextStyle(fontSize: FontSizes.md, color: c.text1),
            ),
          ),
      ],
    );
  }

  /// The right button: the menu of the block under it (which joins the
  /// selection's place when it was not part of it), or of the canvas.
  Future<void> _openMenu(Offset global, Offset p) async {
    final menu = widget.menu;
    if (menu == null) {
      return;
    }
    final b = _blockAt(_blocks, p);
    final i = b?.rowAt(p);
    var ids = _selected;
    if (b != null && !b.selected) {
      widget.onSelect(b.id);
      ids = {b.id};
    }
    final vm = menu.ask(
      FlowMenuAsk(ids, block: b?.id, row: b == null ? null : i),
    );
    final picked = await FlowMenu.show(context, at: global, vm: vm);
    if (!mounted || picked == null) {
      return;
    }
    if (picked == FlowCommand.unpin) {
      vm.unpin?.onPin?.call(false);
      return;
    }
    _run(picked, at: p);
  }

  void _move(PointerMoveEvent e) {
    _pointer = e.position;
    final press = _press;
    if (press == null) {
      return;
    }
    if (!press.dragging &&
        (e.position - press.down).distance < FlowCanvas.slop) {
      return;
    }
    press.dragging = true;
    final p = _local(e.position);
    switch (press) {
      case _Pan():
        _panBy(e.delta);
      case _Marquee():
        final rect = Rect.fromPoints(press.from, p);
        setState(() {
          press
            ..to = p
            ..hit = {
              for (final b in widget.blocks)
                if (b.rect.overlaps(rect)) b.id,
            };
        });
      case _Move(:final anchor, :final grab, :final origins):
        final moving = [
          for (final b in widget.blocks)
            if (origins.containsKey(b.id)) b,
        ];
        final from = origins[anchor];
        if (moving.isEmpty || from == null) {
          return;
        }
        final delta = _inside(moving, p - grab - from);
        setState(
          () => press.at = {
            for (final MapEntry(:key, :value) in origins.entries)
              key: value + delta,
          },
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
        final spot = _Spot(b.id, i, r.id);
        final picked = w.picked;
        w
          ..over = spot
          ..refusal = picked?.spot == spot
              ? null
              : widget.refusal?.ask(
                  BindAsk(w.from, spot.ref, r, replacing: picked?.end),
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
    final p = _local(e.position);
    switch (press) {
      case null:
        return;
      case _Pan():
        break;
      case _Marquee(dragging: false, :final add, :final toggle):
        if (!add && !toggle) {
          widget.onClear();
        }
      case _Marquee(:final hit, :final add, :final toggle):
        if (hit.isEmpty && !add && !toggle) {
          widget.onClear();
        } else {
          widget.onSelectMany?.call(
            BlocksSelected(hit, add: add, toggle: toggle),
          );
        }
      case _Move(dragging: true, :final anchor, :final origins, :final at):
        final from = origins[anchor];
        final to = at[anchor];
        if (from != null && to != null) {
          // The block under the pointer lands on the grid; the others keep
          // their places beside it.
          final delta =
              Offset(FlowCanvas.snap(to.dx), FlowCanvas.snap(to.dy)) - from;
          if (delta != Offset.zero) {
            widget.onMove(
              BlocksMoved({
                for (final MapEntry(:key, :value) in origins.entries)
                  key: value + delta,
              }, nudge: false),
            );
          }
        }
      case _Move(:final anchor, :final narrow):
        if (narrow) {
          widget.onSelect(anchor);
        }
      case _Wire(dragging: false, picked: _Picked(:final spot)):
        _click(spot);
      case _Wire(dragging: false):
        final b = _blockAt(_blocks, p);
        final i = b?.rowAt(p);
        if (b != null && i != null) {
          _click(_Spot(b.id, i, b.rows[i].id));
        } else {
          _lastClick = null;
        }
      case _Wire():
        _drop(press);
      case _Tap(:final spot?):
        _click(spot);
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
        widget.onUnbind(picked.spot.ref);
      }
      return;
    }
    if (w.refusal != null) {
      return;
    }
    final row = _blocks
        .where((b) => b.id == over.block)
        .firstOrNull
        ?.rows
        .where((r) => r.id == over.key)
        .firstOrNull;
    final inPort = row?.inPort;
    if (inPort == null) {
      return;
    }
    final to = PortRefVm(over.block, inPort);
    if (picked == null) {
      widget.onBind(WireDropped(w.from, over.block, inPort));
    } else if (picked.end != to) {
      widget.onRebind(WireMoved(picked.end, to));
    }
  }

  /// A click on row [spot]; the second within 400 ms on a bound input
  /// unbinds it.
  void _click(_Spot spot) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastClick;
    final lastAt = _lastClickAt;
    _lastClick = spot;
    _lastClickAt = now;
    if (last != spot || now - lastAt > Motion.flowDoubleClick) {
      return;
    }
    _lastClick = null;
    final r = widget.blocks
        .where((b) => b.id == spot.block)
        .firstOrNull
        ?.rows
        .where((r) => r.id == spot.key)
        .firstOrNull;
    if (r != null && _bound(r)) {
      widget.onUnbind(spot.ref);
    }
  }

  /// The wheel, and a pinch on the web: ⌘/Ctrl + wheel zooms about the
  /// pointer, the wheel alone scrolls (Shift: sideways).
  void _signal(PointerSignalEvent e) {
    final focal = _viewPoint(e.position);
    switch (e) {
      case PointerScrollEvent(:final scrollDelta):
        if (flowGestureHeld(.zoom, .wheel)) {
          _zoomTo(_scale * math.exp(-scrollDelta.dy / 240), focal: focal);
        } else {
          final sideways =
              HardwareKeyboard.instance.isShiftPressed && scrollDelta.dx == 0;
          _panBy(
            sideways ? Offset(-scrollDelta.dy, 0) : -scrollDelta,
          );
        }
      case PointerScaleEvent(:final scale):
        _zoomTo(_scale * scale, focal: focal);
      default:
        break;
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = _blocks;
    final extent = FlowCanvas.extentOf(blocks);
    final byId = {for (final b in blocks) b.id: b};
    final wire = switch (_press) {
      final _Wire w when w.dragging => w,
      _ => null,
    };
    final marquee = switch (_press) {
      final _Marquee m when m.dragging => m.rect,
      _ => null,
    };
    final picked = wire?.picked;
    final wires = [
      for (final w in widget.wires)
        if (picked == null ||
            w.to != picked.end.block ||
            w.toPort != picked.end.port)
          w,
    ];
    final selected = {
      for (final b in blocks)
        if (b.selected) b.id,
    };
    final front = [
      for (final w in wires)
        if (selected.contains(w.from) || selected.contains(w.to)) w,
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
      cursor: _space
          ? (_press is _Pan
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab)
          : MouseCursor.defer,
      onExit: (_) {
        _pointer = null;
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
              child: DragTarget<PaletteDrag>(
                onAcceptWithDetails: (d) async {
                  final p = _local(d.offset) - FlowCanvas.dropGrab;
                  final extent = FlowCanvas.extentOf(widget.blocks);
                  final write = d.data.writable
                      ? await _readOrWrite(d.offset)
                      : false;
                  if (write == null || !mounted) {
                    return;
                  }
                  d.data.place(
                    PlaceOnCanvas(
                      FlowCanvas.snap(p.dx.clamp(0, extent.width)),
                      FlowCanvas.snap(p.dy.clamp(0, extent.height)),
                      write: write,
                    ),
                  );
                },
                builder: (context, _, _) => Listener(
                  behavior: .opaque,
                  onPointerHover: _hoverAt,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerSignal: _signal,
                  // Two fingers on a trackpad scroll the canvas; a pinch
                  // zooms about where the fingers are.
                  onPointerPanZoomStart: (_) => _pinch = 1,
                  onPointerPanZoomUpdate: (e) {
                    if (e.scale != _pinch) {
                      _zoomTo(
                        _scale * e.scale / _pinch,
                        focal: _viewPoint(e.position),
                      );
                      _pinch = e.scale;
                    }
                    if (e.panDelta != Offset.zero) {
                      _panBy(e.panDelta);
                    }
                  },
                  onPointerCancel: (_) => _cancel(),
                  // The viewer only holds the transform: the canvas pans
                  // and zooms it itself, so that neither fights the marquee.
                  child: InteractiveViewer(
                    transformationController: _ctl,
                    constrained: false,
                    panEnabled: false,
                    scaleEnabled: false,
                    minScale: FlowCanvas.minScale,
                    maxScale: FlowCanvas.maxScale,
                    boundaryMargin: Insets.flowCanvasBoundary,
                    child: SizedBox(
                      key: _key,
                      width: extent.width,
                      height: extent.height,
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
                              child: _block(
                                b,
                                lit: wire?.over?.block == b.id
                                    ? wire!.over!.key
                                    : (hovered?.from == b.id ? source : null),
                                light: wire?.over?.block == b.id
                                    ? light
                                    : RowLight.source,
                              ),
                            ),
                          // The selected blocks' wires over the blocks.
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
                            if (w.firesAtDeploy)
                              if (_mid(byId, w) case final m?)
                                Positioned(
                                  left: m.dx - AppSizes.flowWarnChipWidth / 2,
                                  top: m.dy - AppSizes.flowWarnChip / 2,
                                  width: AppSizes.flowWarnChipWidth,
                                  child: Center(
                                    child: _WarnChip(
                                      S.current.firesAtDeploy,
                                      S.current.firesAtStartNote,
                                    ),
                                  ),
                                ),
                          if (marquee != null)
                            Positioned.fromRect(
                              rect: marquee,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  key: const ValueKey('flow-marquee'),
                                  decoration: BoxDecoration(
                                    color: c.ember.withValues(alpha: 0.08),
                                    border: .all(color: c.ember),
                                    borderRadius: Radii.flowMarquee,
                                  ),
                                ),
                              ),
                            ),
                          if (wire?.refusal case final why?)
                            Positioned(
                              left: wire!.pointer.dx + 14,
                              top: wire.pointer.dy + 12,
                              child: IgnorePointer(
                                child: _Refusal(why.label),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.md,
              right: AppSpacing.md,
              child: Row(
                key: _bar,
                crossAxisAlignment: .end,
                spacing: AppSpacing.sm,
                children: [
                  if (widget.legend)
                    const Flexible(
                      child: IgnorePointer(child: FlowLegend()),
                    ),
                  ListenableBuilder(
                    listenable: _ctl,
                    builder: (context, _) => _CanvasTools(
                      zoom: '${(_scale * 100).round()}%',
                      helpOpen: _help,
                      onZoom: () => _run(.zoomReset),
                      onHelp: () => _run(.help),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.prompt case final ask?)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) => ListenableBuilder(
                    listenable: _ctl,
                    builder: (context, _) {
                      final at = _promptAt(ask, byId, box.biggest);
                      return Stack(
                        children: [
                          Positioned(
                            left: at.dx,
                            top: at.dy,
                            child: ScopePrompt(
                              key: ValueKey('scope-prompt-${ask.block}'),
                              vm: ask,
                              onSave: widget.onPromptSave ?? (_) {},
                              onCancel: widget.onPromptCancel ?? () {},
                              validate: widget.validatePrompt,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            if (_help) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: .opaque,
                  onTap: () => setState(() => _help = false),
                  child: ColoredBox(color: c.ground0.withValues(alpha: 0.55)),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: ShortcutCard(
                      key: const ValueKey('flow-shortcuts'),
                      mac: widget.mac,
                      onClose: () => setState(() => _help = false),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Where the scope prompt stands in the view: under the row it asks
  /// about, at the block's left edge, kept inside the view.
  Offset _promptAt(
    ScopePromptVm ask,
    Map<String, FlowBlockVm> byId,
    Size size,
  ) {
    final b = byId[ask.block];
    if (b == null) {
      return const Offset(24, 24);
    }
    final i = ask.row;
    final under = Offset(
      b.x,
      b.y +
          FlowBlockVm.headerHeight +
          FlowBlockVm.bodyTop +
          FlowBlockVm.rowHeight * ((i < 0 ? 0 : i) + 1) +
          4,
    );
    final at = MatrixUtils.transformPoint(_ctl.value, under);
    return Offset(
      at.dx.clamp(8, math.max(8, size.width - ScopePrompt.width - 8)),
      at.dy.clamp(8, math.max(8, size.height - 230)),
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
    if (w.over case final over? when w.refusal == null) {
      final b = byId[over.block];
      final r = b?.rows.where((r) => r.id == over.key).firstOrNull;
      if (r?.inPort case final port?) {
        p2 = b!.portAt(port, output: false) ?? p2;
      }
    }
    return (p1, p2);
  }
}

/// The zoom (a click: back to 100 %) and the `?` of the shortcut card,
/// beside the legend.
/// A block's widget as built, with what it was built from.
final class _BuiltBlock {
  const _BuiltBlock(this.vm, this.lit, this.light, this.reacts, this.widget);

  final FlowBlockVm vm;
  final String? lit;
  final RowLight light;
  final (bool, bool, bool, bool) reacts;
  final Widget widget;
}

class _CanvasTools extends StatelessWidget {
  const _CanvasTools({
    required this.zoom,
    required this.helpOpen,
    required this.onZoom,
    required this.onHelp,
  });

  final String zoom;
  final bool helpOpen;
  final VoidCallback onZoom;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button({
      required Widget child,
      required String tip,
      required VoidCallback onTap,
      Key? key,
      double? width,
      bool on = false,
    }) => Tooltip(
      message: tip,
      waitDuration: Motion.flowTipWait,
      child: Material(
        key: key,
        color: (on ? c.emberTint : c.ground1).withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.control),
          ),
          side: BorderSide(color: on ? c.emberLine : c.line1),
        ),
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: width,
            height: AppSizes.flowCanvasTool,
            padding: Insets.control,
            alignment: .center,
            child: child,
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: .min,
      spacing: AppSpacing.sm,
      children: [
        button(
          key: const ValueKey('flow-zoom'),
          tip: S.current.scZoomReset,
          onTap: onZoom,
          child: Text(
            zoom,
            style: mono(size: FontSizes.sm, color: c.text3),
          ),
        ),
        button(
          key: const ValueKey('flow-help'),
          tip: S.current.scTitle,
          onTap: onHelp,
          width: AppSizes.flowCanvasTool,
          on: helpOpen,
          child: Text(
            '?',
            style: TextStyle(
              fontSize: FontSizes.lg,
              fontWeight: .w600,
              color: helpOpen ? c.emberSoft : c.text2,
            ),
          ),
        ),
      ],
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
        height: AppSizes.flowWarnChip,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        alignment: .center,
        decoration: BoxDecoration(
          color: c.warnTint,
          border: .all(color: c.warnLine),
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.toggle),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: FontSizes.xs, color: c.warn),
        ),
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
      height: AppSizes.flowRefusal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      alignment: .center,
      decoration: BoxDecoration(
        color: c.badTint,
        border: .all(color: c.badLine),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.segment)),
      ),
      child: Text(
        text,
        style: mono(size: FontSizes.xs, color: c.bad),
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
