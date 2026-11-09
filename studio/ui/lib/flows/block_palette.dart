import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One entry of the palette: a block type, a point or an action of the tree.
final class PaletteEntryVm extends Equatable {
  const PaletteEntryVm({
    required this.id,
    required this.title,
    required this.tag,
    this.group = '',
    this.detail,
    this.point = false,
    this.action = false,
    this.value,
    this.used = false,
    this.dragging = false,
  });

  /// `type:<type>`, `key:<key>` or `act:<key>/<action>`.
  final String id;
  final String title;

  /// A block's role (`IN`, `FX`, `OUT`), a point's type tag (`.0`, `01`,
  /// `≡`, `Aa`) or `ACT`.
  final String tag;

  /// The category it is listed under (a point: the path of its parent).
  final String group;

  /// Searched, and the tooltip of a block (its description: the list shows
  /// none, spec §2).
  final String? detail;

  /// A point or an action of the Tree tab (spec §7).
  final bool point;

  /// An action of the tree: ember, `ACT`.
  final bool action;

  /// A point's live value, or an action's `<n> in`, already formatted.
  final String? value;

  /// The flow already reads it.
  final bool used;

  /// Being dragged now (dashed ember box).
  final bool dragging;

  @override
  List<Object?> get props => [
    id,
    title,
    tag,
    group,
    detail,
    point,
    action,
    value,
    used,
    dragging,
  ];
}

/// A line under the Tree tab: [lead] in its colour, then [text].
final class PaletteNoteVm extends Equatable {
  const PaletteNoteVm(this.lead, this.text, {this.ember = false});

  final String lead;
  final String text;
  final bool ember;

  @override
  List<Object?> get props => [lead, text, ember];
}

/// The left column of the flow editor (spec §2, §7): Blocks (the engine's
/// catalogue by category, one line per block with its tag chip), My blocks
/// and Tree (points and actions to drop on a block or the canvas). Tap an
/// entry to add it, or drag it.
class BlockPalette extends StatefulWidget {
  const BlockPalette({
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.entries,
    required this.onPick,
    this.hint = '',
    this.notes = const [],
    this.closed = const {},
    super.key,
  });

  final List<TabItemVm> tabs;
  final String tab;
  final ValueChanged<String> onTab;
  final List<PaletteEntryVm> entries;
  final ValueChanged<String> onPick;
  final String hint;

  /// Shown at the bottom (the Tree tab says what a drop does).
  final List<PaletteNoteVm> notes;

  /// Groups shown closed at first.
  final Set<String> closed;

  @override
  State<BlockPalette> createState() => _BlockPaletteState();
}

class _BlockPaletteState extends State<BlockPalette> {
  var _q = '';
  late final _closed = <String>{...widget.closed};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.toLowerCase();
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
            tabs: widget.tabs,
            selected: widget.tab,
            onSelect: widget.onTab,
            equal: true,
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.ground3,
                border: .all(color: c.line1),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: Row(
                spacing: 8,
                children: [
                  AppIcon('ui_search', size: 14, color: c.text4),
                  Expanded(
                    child: TextField(
                      onChanged: (s) => setState(() => _q = s),
                      style: TextStyle(fontSize: 13, color: c.text1),
                      decoration:
                          InputDecoration.collapsed(
                            hintText: widget.hint,
                            hintStyle: TextStyle(fontSize: 13, color: c.text4),
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              children: [
                for (final MapEntry(key: g, value: list) in groups.entries) ...[
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
                    for (final e in list)
                      Draggable<String>(
                        data: e.id,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: _Feedback(e.title),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: InkWell(
                            onTap: () => widget.onPick(e.id),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(6),
                            ),
                            child: e.point ? _TreeRow(e) : _BlockRow(e),
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
          if (widget.notes.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 6,
                children: [
                  for (final n in widget.notes)
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
                        fontSize: 12,
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
        height: tree ? 32 : 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            spacing: 6,
            children: [
              RotatedBox(
                quarterTurns: open ? 1 : 0,
                child: AppIcon('ui_chevron_right', size: 12, color: c.text4),
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: tree
                      ? mono(size: 12, color: c.text3)
                      : TextStyle(
                          fontSize: 13,
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
    final (bg, ink) = switch (e.tag) {
      'IN' => (c.goodTint, c.good),
      'OUT' => (c.emberTint, c.emberSoft),
      _ => (c.ground4, c.text2),
    };
    final row = SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 24,
              height: 16,
              alignment: .center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
              child: Text(
                e.tag,
                style: mono(size: 9, weight: .w600, color: ink).copyWith(
                  height: 1.1,
                ),
              ),
            ),
            Expanded(
              child: Text(
                e.title,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(fontSize: 13, color: c.text2),
              ),
            ),
          ],
        ),
      ),
    );
    return switch (e.detail) {
      final d? when d.isNotEmpty => Tooltip(
        message: d,
        waitDuration: const Duration(milliseconds: 500),
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
      height: 32,
      padding: const EdgeInsets.fromLTRB(22, 0, 8, 0),
      decoration: BoxDecoration(
        color: e.dragging ? c.emberFill : (e.used ? c.ground2 : null),
        border: .all(
          color: e.dragging ? c.ember : Colors.transparent,
          width: e.dragging ? 1.5 : 1,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 22,
            child: Text(e.tag, style: mono(size: 10, color: accent)),
          ),
          Expanded(
            child: Text(
              e.title,
              overflow: .ellipsis,
              maxLines: 1,
              style: mono(size: 12, color: c.text2),
            ),
          ),
          if (e.value case final v?)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                v,
                overflow: .ellipsis,
                maxLines: 1,
                style: mono(size: 11, color: accent),
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: .center,
        decoration: BoxDecoration(
          color: c.emberFill,
          border: .all(color: c.ember, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              offset: Offset(0, 10),
              blurRadius: 24,
            ),
          ],
        ),
        child: Text(title, style: mono(size: 12, color: c.emberNew)),
      ),
    );
  }
}
