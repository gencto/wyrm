import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'level_badge.dart';

/// Board *Design system* §05 access level: five segments, filled up to the
/// user's level on a key; the level a change needs is outlined when it is
/// above it.
class AccessMeter extends StatelessWidget {
  const AccessMeter({required this.level, this.needs, super.key});

  /// The user's level.
  final AccessLevel level;

  /// The level a change needs, when shown.
  final AccessLevel? needs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = level.index;
    final need = needs?.index ?? -1;
    final fills = [c.line3, c.muted, c.text4, c.ember];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          spacing: 4,
          children: [
            for (var i = 0; i < AccessLevel.values.length; i++)
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= at ? fills[i.clamp(0, 3)] : c.ground4,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    border: i > at && i <= need
                        ? Border.all(color: c.bad)
                        : (i > at ? Border.all(color: c.muted) : null),
                  ),
                ),
              ),
          ],
        ),
        Row(
          spacing: 4,
          children: [
            for (final (i, l) in AccessLevel.values.indexed)
              Expanded(
                child: Text(
                  l.label,
                  style: mono(
                    size: FontSizes.sm,
                    color: i == at ? c.text1 : c.text3,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
