import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// The `Card` part of a view: a titled group. `variant` (plain, outlined)
/// and `emphasis` (normal, key) are all a document may choose; with
/// [onTap] the whole card opens a page and shows a chevron.
class ViewCard extends StatelessWidget {
  const ViewCard({
    required this.child,
    this.title = '',
    this.outlined = false,
    this.emphasized = false,
    this.onTap,
    super.key,
  });

  final Widget child;
  final String title;

  /// `variant: outlined`: no fill, a line/2 border.
  final bool outlined;

  /// `emphasis: key`: an ember line, for the one card that matters most.
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final body = Padding(
      padding: EdgeInsets.all(d.pad),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: d.gap,
        children: [
          if (title.isNotEmpty || onTap != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: boardText(
                      size: d.label + 1,
                      weight: .w600,
                      color: c.text1,
                    ),
                  ),
                ),
                if (onTap != null)
                  AppIcon('ui_chevron_right', size: 16, color: c.text4),
              ],
            ),
          child,
        ],
      ),
    );
    return ViewCardScope(
      child: Material(
        color: outlined ? Colors.transparent : c.ground1,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(
            color: emphasized
                ? c.emberLine
                : outlined
                ? c.line2
                : c.line1,
          ),
        ),
        clipBehavior: .antiAlias,
        child: onTap == null
            ? body
            : InkWell(
                onTap: onTap,
                hoverColor: c.text1.withValues(alpha: 0.04),
                child: body,
              ),
      ),
    );
  }
}

/// Marks what is drawn inside a [ViewCard], so a value there is not given
/// a tile of its own.
class ViewCardScope extends InheritedWidget {
  const ViewCardScope({required super.child, super.key});

  static bool inside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ViewCardScope>() != null;

  @override
  bool updateShouldNotify(ViewCardScope old) => false;
}
