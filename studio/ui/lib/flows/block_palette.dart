import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
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
  });

  /// `type:<type>` or `key:<key>`.
  final String id;
  final String title;
  final String tag;

  /// The category it is listed under.
  final String group;
  final String? detail;

  @override
  List<Object?> get props => [id, title, tag, group, detail];
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
                  prefixIcon: Icon(Icons.search, size: 16, color: c.text4),
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
                          Icon(
                            _closed.contains(g)
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 16,
                            color: c.text4,
                          ),
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
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 6, 8, 6),
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
                                    borderRadius: BorderRadius.circular(4),
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
                                          style: mono(size: 11, color: c.text4),
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
