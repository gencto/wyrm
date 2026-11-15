import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/segmented_tabs.dart';
import '../indicators/app_icon.dart';
import '../indicators/value_type.dart';
import '../models/disabled.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../trees/tree_row.dart';
import 'custom_block_dialog.dart';
import 'flow_intents.dart';

/// The tabs of the palette (spec §2, §18, §20).
enum PaletteTabVm {
  blocks,
  my,
  tree;

  String get label => switch (this) {
    blocks => S.current.paletteBlocks,
    my => S.current.paletteMyBlocks,
    tree => S.current.paletteTree,
  };

  /// What the search field hints.
  String get searchHint => switch (this) {
    tree => S.current.findInTree,
    blocks || my => S.current.findBlock,
  };

  /// Said in place of the list when there is nothing to list.
  String get empty => switch (this) {
    blocks => '',
    my => S.current.myBlocksEmpty,
    tree => S.current.treeEmpty,
  };
}

/// What an entry of the palette is, with its chip: a source of the
/// catalogue (`IN`, teal), a sink (`OUT`, ember), any other block (`FX`),
/// a custom block of this flow (`MY`) or of the site's library (`LIB`).
enum PaletteKindVm {
  input('IN'),
  output('OUT'),
  logic('FX'),
  my('MY'),
  library('LIB');

  const PaletteKindVm(this.tag);

  /// The chip's letters (a glyph, not a word: never translated).
  final String tag;
}

/// What is dragged out of the palette: its name (the feedback), whether
/// it may also be written (a writable point: let go on the canvas it asks
/// `Read` or `Write`, Alt held writes at once), whether it is a point that
/// may be let go on a block's input, and how it is placed.
final class PaletteDrag extends Equatable {
  const PaletteDrag(
    this.title, {
    required this.place,
    this.writable = false,
    this.point = false,
  });

  final String title;
  final bool writable;
  final bool point;

  /// Places it: tapped, let go on the canvas or on a block's input.
  final ValueChanged<Place> place;

  // [place] is behaviour (value_changed.dart): not compared.
  @override
  List<Object?> get props => [title, writable, point];
}

/// One entry of the palette: a block type, a custom block, or (on the
/// board of the Tree tab) a point or an action of the tree. [place] puts
/// it on the canvas; a custom block's menu picks go to [onMenu], its new
/// name to [onRename].
final class PaletteEntryVm extends Equatable {
  const PaletteEntryVm({
    required this.title,
    required this.place,
    this.kind = PaletteKindVm.logic,
    this.glyph,
    this.category = '',
    this.wire,
    this.description,
    this.point = false,
    this.action = false,
    this.value,
    this.used = false,
    this.dragging = false,
    this.instances,
    this.updateTo,
    this.version,
    this.inputs,
    this.insideItself = false,
    this.menu = const [],
    this.onMenu,
    this.onRename,
  });

  final String title;

  /// Places it: tapped, dragged onto the canvas or onto a block's input.
  final ValueChanged<Place> place;
  final PaletteKindVm kind;

  /// A chip of its own in place of the kind's: a point's type tag (`.0`,
  /// `01`, `Aa`, [ValueType.tag]) or a category's own letters.
  final String? glyph;

  /// The catalogue's category it is listed under (a point: the path of
  /// its parent); a custom block is listed under its own group.
  final String category;

  /// The engine's name of a block type (`scale`), searched and shown in
  /// its tooltip before its [description].
  final String? wire;
  final String? description;

  /// A point or an action of the Tree tab (spec §7).
  final bool point;

  /// An action of the tree: ember, `ACT`.
  final bool action;

  /// A point's live value, as the tree shows it.
  final String? value;

  /// The flow already reads it.
  final bool used;

  /// Being dragged now (dashed ember box).
  final bool dragging;

  /// A custom block of this flow: how many instances use it ([updateTo]:
  /// the library has a newer version, said instead).
  final int? instances;
  final int? updateTo;

  /// A block of the site's library: its version.
  final int? version;

  /// An action of the tree: how many inputs it takes.
  final int? inputs;

  /// It cannot be placed: the canvas is inside this very block.
  final bool insideItself;

  /// Its context menu (a custom block: `Save to library`, `Rename`, …).
  final List<PaletteMenuItemVm> menu;

  /// An item of [menu] picked ([MyBlockItemVm.rename] asks the name first
  /// and goes to [onRename]).
  final ValueChanged<MyBlockItemVm>? onMenu;
  final ValueChanged<String>? onRename;

  /// The chip's letters.
  String get tag => glyph ?? (action ? 'ACT' : kind.tag);

  /// The group it is listed under.
  String get group => switch (kind) {
    PaletteKindVm.my => S.current.myBlocksThisFlow,
    PaletteKindVm.library => S.current.myBlocksLibrary,
    PaletteKindVm.input ||
    PaletteKindVm.output ||
    PaletteKindVm.logic => category,
  };

  /// Searched, and the tooltip (the list shows no description, spec §2).
  String? get detail => switch ((wire, description)) {
    (final w?, final d?) when d.isNotEmpty => '$w: $d',
    (final w?, _) => w,
    (null, final d) => d,
  };

  /// What the right of its row says.
  String? get valueText => switch (this) {
    PaletteEntryVm(inputs: final n?) => S.current.actionInputs(n),
    PaletteEntryVm(updateTo: final v?) => S.current.mbUpdateTo(v),
    PaletteEntryVm(instances: final n?) => S.current.mbUsed(n),
    PaletteEntryVm(version: final v?) => S.current.mbVersion(v),
    _ => value,
  };

  /// The entry's widget key (what tests find it by).
  String get widgetKey => switch (kind) {
    PaletteKindVm.my => 'palette-type:block:$title',
    PaletteKindVm.library => 'palette-lib:$title',
    PaletteKindVm.input ||
    PaletteKindVm.output ||
    PaletteKindVm.logic => 'palette-$title',
  };

  /// Why it cannot be placed; null: it can.
  String? get disabledReason =>
      insideItself ? const FlowOff(.insideItself).text : null;

  // The callbacks are behaviour (value_changed.dart): not compared.
  @override
  List<Object?> get props => [
    title,
    kind,
    glyph,
    category,
    wire,
    description,
    point,
    action,
    value,
    used,
    dragging,
    instances,
    updateTo,
    version,
    inputs,
    insideItself,
    menu,
  ];
}

/// An item of a custom block's menu (spec §20).
enum MyBlockItemVm {
  edit,
  save,
  rename,
  update,
  delete,
  removeLibrary;

  String get label => switch (this) {
    edit => S.current.mbEdit,
    save => S.current.mbSave,
    rename => S.current.mbRename,
    update => S.current.mbUpdate,
    delete => S.current.mbDelete,
    removeLibrary => S.current.mbRemoveLibrary,
  };

  /// Drawn in coral: it deletes.
  bool get danger => this == delete || this == removeLibrary;
}

/// One item of a palette entry's context menu, and why it is off.
final class PaletteMenuItemVm extends Equatable {
  const PaletteMenuItemVm(this.item, {this.off});

  final MyBlockItemVm item;

  /// Why it cannot be picked (its tooltip); null: it can.
  final Disabled? off;

  @override
  List<Object?> get props => [item, off];
}

/// A row of the Tree tab (spec §18): a node or a value of the site's
/// tree, or an action of an open node. A row that [place]s something is
/// dragged onto the canvas, and a tap adds it; any other opens or closes.
sealed class PaletteTreeRowVm extends Equatable {
  const PaletteTreeRowVm({
    required this.key,
    required this.name,
    required this.depth,
  });

  /// The node's key (an action's: `<node>/~act/<name>`).
  final String key;
  final String name;
  final int depth;

  /// Places what it stands for; null: it opens or closes.
  ValueChanged<Place>? get place;

  /// May be let go on a block's input (a value).
  bool get point;

  /// May also be written (a writable value).
  bool get writable;

  /// The row as the Explorer's tree draws it.
  TreeRowVm get row;

  /// The row's widget key (what tests find it by).
  String get widgetKey;
}

/// A node or a value of the tree.
final class PaletteNodeRowVm extends PaletteTreeRowVm {
  const PaletteNodeRowVm({
    required super.key,
    required super.name,
    required super.depth,
    this.icon = 'node_section',
    this.opens = false,
    this.open = false,
    this.used = false,
    this.type,
    this.value,
    this.place,
    this.writable = false,
  });

  final String icon;

  /// It may open (it has, or may have, children or actions).
  final bool opens;
  final bool open;

  /// A block of the flow reads or writes it.
  final bool used;

  /// A value's type (its tag); null for a node.
  final ValueType? type;

  /// A value's live value, as the tree shows it.
  final String? value;
  @override
  final ValueChanged<Place>? place;
  @override
  final bool writable;

  @override
  bool get point => type != null;

  @override
  String get widgetKey => place == null ? 'tree-$key' : 'tree-key:$key';

  @override
  TreeRowVm get row => TreeRowVm(
    id: key,
    name: name,
    depth: depth,
    icon: icon,
    hasChildren: opens,
    expanded: open,
    marked: used,
    tag: type?.tag,
    value: value,
  );

  @override
  List<Object?> get props => [
    key,
    name,
    depth,
    icon,
    opens,
    open,
    used,
    type,
    value,
    writable,
  ];
}

/// An action of an open node: dragged, a block that runs it.
final class PaletteActionRowVm extends PaletteTreeRowVm {
  const PaletteActionRowVm({
    required super.key,
    required super.name,
    required super.depth,
    required this.node,
    required this.action,
    required this.place,
    required this.inputs,
  });

  /// The node's key and the action's own name.
  final String node;
  final String action;

  @override
  final ValueChanged<Place> place;

  @override
  String get widgetKey => 'tree-act:$node/$action';

  @override
  bool get point => false;

  @override
  bool get writable => false;

  /// How many inputs the action takes.
  final int inputs;

  @override
  TreeRowVm get row => TreeRowVm(
    id: key,
    name: name,
    depth: depth,
    tag: 'ACT',
    ember: true,
    value: S.current.actionInputs(inputs),
  );

  @override
  List<Object?> get props => [key, name, depth, node, action, inputs];
}

/// A line under the Tree tab: [lead] in its colour, then [text].
final class _Note {
  const _Note(this.lead, this.text, {this.ember = false});

  final String lead;
  final String text;
  final bool ember;
}

/// The left column of the flow editor (spec §2, §7): Blocks (the engine's
/// catalogue by category, one line per block with its tag chip), My blocks
/// and Tree (points and actions to drop on a block or the canvas). Tap an
/// entry to add it, or drag it.
/// Asks the palette on screen to put the cursor in its search field: add
/// one to it (`/` or ⌘/Ctrl+K in the flow editor, spec §14).
final paletteSearchRequest = ValueNotifier<int>(0);

class BlockPalette extends StatefulWidget {
  const BlockPalette({
    required this.tab,
    required this.onTab,
    required this.entries,
    this.myBlocksOff = false,
    this.closed = const {},
    this.tree,
    this.onTreeToggle,
    this.onQuery,
    this.checkName,
    super.key,
  });

  /// The Tree tab: the site's tree as rows in display order, drawn with
  /// the Explorer's [TreeRow] (flow-editor.md §18). A row that places
  /// something is a value leaf or an action: it is dragged onto the
  /// canvas, and a tap adds it; any other row opens or closes. Null:
  /// [entries] are listed.
  final List<PaletteTreeRowVm>? tree;
  final ValueChanged<String>? onTreeToggle;

  /// What is typed in the search field while the tree is shown: the rows
  /// are filtered where they are made.
  final ValueChanged<String>? onQuery;

  /// Why a new name of a custom block is refused (Rename); null: taken.
  final Validate<String>? checkName;

  final PaletteTabVm tab;
  final ValueChanged<PaletteTabVm> onTab;
  final List<PaletteEntryVm> entries;

  /// The broker has no custom blocks: the My blocks tab is off.
  final bool myBlocksOff;

  /// Groups shown closed at first.
  final Set<String> closed;

  @override
  State<BlockPalette> createState() => _BlockPaletteState();
}

class _BlockPaletteState extends State<BlockPalette> {
  var _q = '';
  late final _closed = <String>{...widget.closed};
  final _search = FocusNode(debugLabel: 'BlockPalette search');

  @override
  void initState() {
    super.initState();
    paletteSearchRequest.addListener(_search.requestFocus);
  }

  @override
  void dispose() {
    paletteSearchRequest.removeListener(_search.requestFocus);
    _search.dispose();
    super.dispose();
  }

  /// One entry: dragged onto the canvas, or tapped to add it; its context
  /// menu on the right button. An entry that cannot be placed does neither.
  Widget _entry(PaletteEntryVm e) {
    final row = e.point ? _TreeRow(e) : _BlockRow(e);
    final off = e.disabledReason != null;
    final tile = MouseRegion(
      cursor: off ? MouseCursor.defer : SystemMouseCursors.grab,
      child: InkWell(
        onTap: off ? null : () => e.place(const PlaceTapped()),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.segment)),
        child: row,
      ),
    );
    final dragged = off
        ? tile
        : Draggable<PaletteDrag>(
            data: PaletteDrag(e.title, place: e.place, point: e.point),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _Feedback(e.title),
            child: tile,
          );
    if (e.menu.isEmpty) {
      return dragged;
    }
    return GestureDetector(
      key: ValueKey(e.widgetKey),
      onSecondaryTapUp: (d) => unawaited(_menu(e, d.globalPosition)),
      onLongPressStart: (d) => unawaited(_menu(e, d.globalPosition)),
      child: dragged,
    );
  }

  Future<void> _menu(PaletteEntryVm e, Offset at) async {
    final c = context.colors;
    final picked = await showMenu<MyBlockItemVm>(
      context: context,
      color: c.ground3,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final m in e.menu)
          PopupMenuItem(
            value: m.item,
            height: AppSizes.flowMenuItem,
            enabled: m.off == null,
            child: Tooltip(
              message: m.off?.text ?? '',
              child: Text(
                m.item.label,
                style: TextStyle(
                  fontSize: FontSizes.md,
                  color: m.off != null
                      ? c.muted
                      : (m.item.danger ? c.bad : c.text1),
                ),
              ),
            ),
          ),
      ],
    );
    if (picked == null || !mounted) {
      return;
    }
    if (picked != MyBlockItemVm.rename) {
      e.onMenu?.call(picked);
      return;
    }
    // Rename asks for the new name first.
    final name = await NameDialog.ask(
      context,
      title: S.current.mbRename,
      value: e.title,
      confirm: S.current.mbRename,
      cancel: S.current.cancel,
      validate: widget.checkName,
    );
    if (name != null) {
      e.onRename?.call(name);
    }
  }

  /// A row of the Tree tab: the Explorer's row, 32 high. A value leaf or
  /// an action is dragged (and added by a tap); a node opens or closes.
  Widget _treeRow(PaletteTreeRowVm r) {
    final place = r.place;
    final row = TreeRow(
      key: ValueKey(r.widgetKey),
      vm: r.row,
      height: AppSizes.flowPaletteRow,
      onTap: (id) => place == null
          ? widget.onTreeToggle?.call(id)
          : place(const PlaceTapped()),
      onToggle: widget.onTreeToggle,
    );
    if (place == null) {
      return row;
    }
    return Draggable<PaletteDrag>(
      data: PaletteDrag(
        r.name,
        place: place,
        writable: r.writable,
        point: r.point,
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _Feedback(r.name),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.toLowerCase();
    final tab = widget.tab;
    final empty = tab.empty;
    final notes = tab == PaletteTabVm.tree
        ? [
            _Note(S.current.treePoint, S.current.treePointNote2),
            _Note(S.current.treeAction, S.current.treeActionNote2, ember: true),
          ]
        : const <_Note>[];
    final shown = [
      for (final e in widget.entries)
        if (q.isEmpty ||
            '${e.title} ${e.detail ?? ''}'.toLowerCase().contains(q))
          e,
    ];
    final groups = <String, List<PaletteEntryVm>>{};
    for (final e in shown) {
      (groups[e.group] ??= []).add(e);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SegmentedTabs(
            tabs: [
              for (final t in PaletteTabVm.values)
                TabItemVm(
                  id: t,
                  label: t.label,
                  disabledReason: t == PaletteTabVm.my && widget.myBlocksOff
                      ? const FlowOff(.noCustomBlocks).text
                      : null,
                ),
            ],
            selected: tab,
            onSelect: widget.onTab,
            equal: true,
          ),
          Padding(
            padding: Insets.flowPaletteSearch,
            child: Container(
              height: AppSizes.flowField,
              padding: Insets.control,
              decoration: BoxDecoration(
                color: c.ground3,
                border: .all(color: c.line1),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadii.segment),
                ),
              ),
              child: Row(
                spacing: AppSpacing.sm,
                children: [
                  AppIcon(
                    'ui_search',
                    size: AppSizes.flowSearchIcon,
                    color: c.text4,
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: _search,
                      onChanged: (s) {
                        if (widget.tree != null) {
                          widget.onQuery?.call(s);
                        }
                        setState(() => _q = s);
                      },
                      style: TextStyle(fontSize: FontSizes.md, color: c.text1),
                      decoration:
                          InputDecoration.collapsed(
                            hintText: tab.searchHint,
                            hintStyle: TextStyle(
                              fontSize: FontSizes.md,
                              color: c.text4,
                            ),
                          ).copyWith(
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.tree case final rows?)
            Expanded(
              child: rows.isEmpty
                  ? _Empty(empty)
                  : ListView.builder(
                      padding: Insets.flowPaletteList,
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _treeRow(rows[i]),
                    ),
            )
          else if (shown.isEmpty && empty.isNotEmpty)
            Expanded(child: _Empty(empty))
          else
            Expanded(
              child: ListView(
                padding: Insets.flowPaletteList,
                children: [
                  for (final MapEntry(key: g, value: list)
                      in groups.entries) ...[
                    _Group(
                      name: g,
                      tree: list.first.point,
                      open: !_closed.contains(g),
                      onTap: () => setState(
                        () => _closed.contains(g)
                            ? _closed.remove(g)
                            : _closed.add(g),
                      ),
                    ),
                    if (!_closed.contains(g))
                      for (final e in list) _entry(e),
                  ],
                ],
              ),
            ),
          if (notes.isNotEmpty)
            Container(
              padding: Insets.flowPaletteNotes,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Column(
                crossAxisAlignment: .start,
                spacing: AppSpacing.flowLines,
                children: [
                  for (final n in notes)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: n.lead,
                            style: TextStyle(
                              color: n.ember ? c.emberSoft : c.text2,
                            ),
                          ),
                          TextSpan(text: ' ${n.text}'),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        height: 1.45,
                        color: c.text4,
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

/// Nothing to list, and why.
class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.none,
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: FontSizes.sm,
        height: 1.45,
        color: context.colors.text4,
      ),
    ),
  );
}

/// A category (13/600) or a parent of points (mono 12), with its chevron.
class _Group extends StatelessWidget {
  const _Group({
    required this.name,
    required this.tree,
    required this.open,
    required this.onTap,
  });

  final String name;
  final bool tree;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = name.isEmpty
        ? '—'
        : (tree ? name : '${name[0].toUpperCase()}${name.substring(1)}');
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: tree ? AppSizes.flowPaletteRow : AppSizes.flowPaletteGroup,
        child: Padding(
          padding: Insets.flowPaletteGroup,
          child: Row(
            spacing: AppSpacing.flowRowParts,
            children: [
              RotatedBox(
                quarterTurns: open ? 1 : 0,
                child: AppIcon(
                  'ui_chevron_right',
                  size: AppSizes.flowGroupChevron,
                  color: c.text4,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: tree
                      ? mono(size: FontSizes.sm, color: c.text3)
                      : TextStyle(
                          fontSize: FontSizes.md,
                          fontWeight: .w600,
                          color: c.text2,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A block type: one line, 32 high, its tag chip and its name; the
/// description is the tooltip.
class _BlockRow extends StatelessWidget {
  const _BlockRow(this.e);

  final PaletteEntryVm e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, ink) = switch (e.kind) {
      PaletteKindVm.input => (c.goodTint, c.good),
      PaletteKindVm.output => (c.emberTint, c.emberSoft),
      PaletteKindVm.logic ||
      PaletteKindVm.my ||
      PaletteKindVm.library => (c.ground4, c.text2),
    };
    final row = SizedBox(
      height: AppSizes.flowPaletteRow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.none,
          AppSpacing.sm,
          AppSpacing.none,
        ),
        child: Row(
          spacing: AppSpacing.flowPaletteRow,
          children: [
            Container(
              width: AppSizes.flowPaletteTag.width,
              height: AppSizes.flowPaletteTag.height,
              alignment: .center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadii.mark),
                ),
              ),
              child: Text(
                e.tag,
                style:
                    mono(
                      size: FontSizes.flowTag,
                      weight: .w600,
                      color: ink,
                    ).copyWith(
                      height: 1.1,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                e.title,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: FontSizes.md,
                  color: e.disabledReason == null ? c.text2 : c.muted,
                ),
              ),
            ),
            if (e.valueText case final v?)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.flowPaletteValue,
                ),
                child: Text(
                  v,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: mono(size: FontSizes.xs, color: c.text4),
                ),
              ),
          ],
        ),
      ),
    );
    return switch (e.disabledReason ?? e.detail) {
      final d? when d.isNotEmpty => Tooltip(
        message: d,
        waitDuration: Motion.flowTipWait,
        child: row,
      ),
      _ => row,
    };
  }
}

/// A point or an action of the Tree tab (board *FlowTree*): 32 high, its
/// tag, its mono name and its value or input count on the right.
class _TreeRow extends StatelessWidget {
  const _TreeRow(this.e);

  final PaletteEntryVm e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = e.action ? c.emberSoft : c.text4;
    return Container(
      height: AppSizes.flowPaletteRow,
      padding: Insets.flowPaletteTreeRow,
      decoration: BoxDecoration(
        color: e.dragging ? c.emberFill : (e.used ? c.ground2 : null),
        border: .all(
          color: e.dragging ? c.ember : Colors.transparent,
          width: e.dragging ? 1.5 : 1,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.segment)),
      ),
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          SizedBox(
            width: AppSizes.flowPaletteTreeTag,
            child: Text(
              e.tag,
              style: mono(size: FontSizes.flowDetail, color: accent),
            ),
          ),
          Expanded(
            child: Text(
              e.title,
              overflow: .ellipsis,
              maxLines: 1,
              style: mono(size: FontSizes.sm, color: c.text2),
            ),
          ),
          if (e.valueText case final v?)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.flowPaletteTreeValue,
              ),
              child: Text(
                v,
                overflow: .ellipsis,
                maxLines: 1,
                style: mono(size: FontSizes.xs, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        height: AppSizes.flowPaletteRow,
        padding: Insets.control,
        alignment: .center,
        decoration: BoxDecoration(
          color: c.emberFill,
          border: .all(color: c.ember, width: 1.5),
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.segment),
          ),
          boxShadow: const [
            BoxShadow(
              color: Shades.popupShadow,
              offset: Offset(0, 10),
              blurRadius: 24,
            ),
          ],
        ),
        child: Text(
          title,
          style: mono(size: FontSizes.sm, color: c.emberNew),
        ),
      ),
    );
  }
}
