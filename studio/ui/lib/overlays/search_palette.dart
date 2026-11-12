import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One entry of the search palette.
final class SearchEntryVm extends Equatable {
  const SearchEntryVm({
    required this.id,
    required this.title,
    required this.icon,
    this.detail,
  });

  /// What the composer gets back: `tab:links`, `key:wy/…`, `site:plant`.
  final String id;
  final String title;
  final String icon;
  final String? detail;

  @override
  List<Object?> get props => [id, title, icon, detail];
}

/// ⌘K: type to filter workspaces, sites, links and loaded nodes; a typed key
/// (`wy/…` or relative to the site) is offered as "Go to".
class SearchPalette extends StatefulWidget {
  const SearchPalette({
    required this.entries,
    required this.onPick,
    required this.goTo,
    this.hint = 'Go to a node, action or link',
    super.key,
  });

  final List<SearchEntryVm> entries;
  final ValueChanged<String> onPick;

  /// Builds the "Go to" entry for a typed key, or null.
  final SearchEntryVm? Function(String text) goTo;
  final String hint;

  /// Opens the palette as a dialog; the picked id or null.
  static Future<String?> show(
    BuildContext context, {
    required List<SearchEntryVm> entries,
    required SearchEntryVm? Function(String text) goTo,
    String hint = 'Go to a node, action or link',
  }) => showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Align(
      alignment: const Alignment(0, -0.6),
      child: SearchPalette(
        entries: entries,
        goTo: goTo,
        hint: hint,
        onPick: (id) => Navigator.of(context).pop(id),
      ),
    ),
  );

  @override
  State<SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends State<SearchPalette> {
  var _text = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _text.trim().toLowerCase();
    final hits = [
      ?widget.goTo(_text.trim()),
      for (final e in widget.entries)
        if (q.isEmpty ||
            e.title.toLowerCase().contains(q) ||
            (e.detail?.toLowerCase().contains(q) ?? false))
          e,
    ].take(40).toList();
    return Material(
      color: c.ground1,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 460),
        child: Column(
          mainAxisSize: .min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                style: TextStyle(fontSize: 14, color: c.text1),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AppIcon('ui_search', size: 16, color: c.text3),
                  ),
                ),
                onChanged: (s) => setState(() => _text = s),
                onSubmitted: (_) {
                  if (hits.isNotEmpty) {
                    widget.onPick(hits.first.id);
                  }
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (final h in hits)
                    InkWell(
                      onTap: () => widget.onPick(h.id),
                      borderRadius: Radii.segment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          spacing: 12,
                          children: [
                            AppIcon(h.icon, size: 16, color: c.text3),
                            Expanded(
                              child: Text(
                                h.title,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(fontSize: 14, color: c.text1),
                              ),
                            ),
                            if (h.detail case final d?)
                              Flexible(
                                child: Text(
                                  d,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: mono(size: 12, color: c.text4),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
