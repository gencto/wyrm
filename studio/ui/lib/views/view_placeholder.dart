import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// What a view shows in place of a part the catalog does not have: a
/// dashed-looking card that names the part, so the rest of the view still
/// draws and the Checks tab says why.
class ViewPlaceholder extends StatelessWidget {
  const ViewPlaceholder({required this.part, this.id = '', super.key});

  /// The component type the document asked for (`Gauge`).
  final String part;

  /// The component's id, shown in mono.
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    return Container(
      padding: EdgeInsets.all(d.pad),
      decoration: BoxDecoration(
        color: c.ground2,
        borderRadius: Radii.card,
        border: .all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        spacing: 2,
        children: [
          Text(
            S.current.viewsUnknownPart(part),
            style: boardText(size: d.label, color: c.text3),
          ),
          if (id.isNotEmpty)
            Text(id, style: boardText(size: 12, color: c.text4, code: true)),
        ],
      ),
    );
  }
}
