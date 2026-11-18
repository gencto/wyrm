import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One entry of the search palette.
final class SearchEntryVm<T> extends Equatable {
  const SearchEntryVm({
    required this.id,
    required this.title,
    required this.icon,
    this.detail,
  });

  /// What the composer gets back: a workspace, a site, a key — of the
  /// type the caller names.
  final T id;
  final String title;
  final AppIcon icon;
  final String? detail;

  @override
  List<Object?> get props => [id, title, icon, detail];
}

/// ⌘K: type to filter workspaces, sites, links and loaded nodes; a typed key
/// (`wy/…` or relative to the site) is offered as "Go to".
///
/// A pick closes it with the entry's id ([show]'s answer).
class SearchPalette<T> extends StatefulWidget {
  const SearchPalette({
    required this.entries,
    required this.goTo,
    this.hint = 'Go to a node, action or link',
    super.key,
  });

  final List<SearchEntryVm<T>> entries;

  /// Builds the "Go to" entry for a typed key, or null.
  final SearchEntryVm<T>? Function(String text) goTo;
  final String hint;

  /// Opens the palette as a dialog; the picked id or null.
  static Future<T?> show<T>(
    BuildContext context, {
    required List<SearchEntryVm<T>> entries,
    required SearchEntryVm<T>? Function(String text) goTo,
    String hint = 'Go to a node, action or link',
  }) => showDialog<T>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Align(
      alignment: const Alignment(0, -0.6),
      child: SearchPalette<T>(entries: entries, goTo: goTo, hint: hint),
    ),
  );

  @override
  State<SearchPalette<T>> createState() => _SearchPaletteState<T>();
}

class _SearchPaletteState<T> extends State<SearchPalette<T>> {
  void _pick(T id) => Navigator.of(context).pop(id);

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
                style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AppIconView(
                      AppIcon.uiSearch,
                      size: IconSizes.md,
                      color: c.text3,
                    ),
                  ),
                ),
                onChanged: (s) => setState(() => _text = s),
                onSubmitted: (_) {
                  if (hits.isNotEmpty) {
                    _pick(hits.first.id);
                  }
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.none,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                children: [
                  for (final h in hits)
                    InkWell(
                      onTap: () => _pick(h.id),
                      borderRadius: Radii.segment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          spacing: 12,
                          children: [
                            AppIconView(
                              h.icon,
                              size: IconSizes.md,
                              color: c.text3,
                            ),
                            Expanded(
                              child: Text(
                                h.title,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  fontSize: FontSizes.lg,
                                  color: c.text1,
                                ),
                              ),
                            ),
                            if (h.detail case final d?)
                              Flexible(
                                child: Text(
                                  d,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: mono(
                                    size: FontSizes.sm,
                                    color: c.text4,
                                  ),
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
