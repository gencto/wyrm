import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One entry of the palette: a block type or a point of the tree.
final class PaletteEntryVm extends Equatable {
  const PaletteEntryVm({
    required this.id,
    required this.title,
    required this.tag,
    this.group = '',
    this.detail,
    this.point = false,
    this.value,
  });

  /// `type:<type>` or `key:<key>`.
  final String id;
  final String title;

  /// A block's role (`IN`, `FX`, `OUT`) or a point's type tag (`.0`, `01`,
  /// `≡`, `Aa`).
  final String tag;

  /// The category it is listed under (a point: the path of its parent).
  final String group;

  /// Searched, and shown under a block's title.
  final String? detail;

  /// A point of the Tree tab: one line of tag, mono name and [value]
  /// (docs/design/specs/flow-editor.md §7).
  final bool point;

  /// A point's live value, already formatted.
  final String? value;

  @override
  List<Object?> get props => [id, title, tag, group, detail, point, value];
}

/// The left column of the flow editor: Blocks (the engine's catalogue by
/// category) and Tree (points to drop as a subscribe block). Tap an entry
/// to add it, or drag it onto the canvas.
class BlockPalette extends StatefulWidget {
  const BlockPalette({
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.entries,
    required this.onPick,
    this.hint = '',
    super.key,
  });

  final List<TabItemVm> tabs;
  final String tab;
  final ValueChanged<String> onTab;
  final List<PaletteEntryVm> entries;
  final ValueChanged<String> onPick;
  final String hint;

  @override
  State<BlockPalette> createState() => _BlockPaletteState();
}

class _BlockPaletteState extends State<BlockPalette> {
  var _q = '';
  final _closed = <String>{};

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
    return Container(
      width: 240,
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
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (s) => setState(() => _q = s),
                style: TextStyle(fontSize: 13, color: c.text1),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AppIcon('ui_search', size: 16, color: c.text4),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                for (final MapEntry(key: g, value: list) in groups.entries) ...[
                  InkWell(
                    onTap: () => setState(
                      () => _closed.contains(g)
                          ? _closed.remove(g)
                          : _closed.add(g),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        spacing: 6,
                        children: [
                          AnimatedRotation(
                            turns: _closed.contains(g) ? 0 : 0.25,
                            duration: const Duration(milliseconds: 120),
                            child: AppIcon(
                              'ui_chevron_right',
                              size: list.first.point ? 12 : 16,
                              color: c.text4,
                            ),
                          ),
                          if (list.first.point)
                            Expanded(
                              child: Text(
                                g.isEmpty ? '—' : g,
                                overflow: .ellipsis,
                                style: mono(size: 12, color: c.text3),
                              ),
                            )
                          else
                            Text(
                              g.isEmpty
                                  ? '—'
                                  : '${g[0].toUpperCase()}${g.substring(1)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: .w600,
                                color: c.text1,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!_closed.contains(g))
                    for (final e in list)
                      Draggable<String>(
                        data: e.id,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: c.ground3,
                              border: .all(color: c.ember),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              e.title,
                              style: mono(size: 12, color: c.text1),
                            ),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => widget.onPick(e.id),
                          child: e.point
                              ? _PointRow(e)
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    28,
                                    6,
                                    8,
                                    6,
                                  ),
                                  child: Row(
                                    spacing: 10,
                                    children: [
                                      Container(
                                        width: 30,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 1,
                                        ),
                                        alignment: .center,
                                        decoration: BoxDecoration(
                                          color: c.ground4,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          e.tag,
                                          style: mono(
                                            size: 9,
                                            weight: .w600,
                                            color: c.text2,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: .start,
                                          children: [
                                            Text(
                                              e.title,
                                              overflow: .ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: c.text1,
                                              ),
                                            ),
                                            if (e.detail case final d?)
                                              Text(
                                                d,
                                                overflow: .ellipsis,
                                                style: mono(
                                                  size: 11,
                                                  color: c.text4,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A point of the Tree tab: 32 high, its type tag (mono 10), its name (mono
/// 12) and its live value on the right (mono 11), as board *FlowTree*.
class _PointRow extends StatelessWidget {
  const _PointRow(this.e);

  final PaletteEntryVm e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 32,
      padding: const EdgeInsets.fromLTRB(22, 0, 8, 0),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 22,
            child: Text(e.tag, style: mono(size: 10, color: c.text4)),
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
                style: mono(size: 11, color: c.text4),
              ),
            ),
        ],
      ),
    );
  }
}
