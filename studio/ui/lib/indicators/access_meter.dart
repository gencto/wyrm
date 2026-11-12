import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// Board *Design system* §05 access level: five segments, filled up to the
/// user's level on a key; the level a change needs is outlined when it is
/// above it.
class AccessMeter extends StatelessWidget {
  const AccessMeter({required this.level, this.needs, super.key});

  /// The user's level: `none`, `list`, `read`, `write` or `config`.
  final String level;

  /// The level a change needs, when shown.
  final String? needs;

  static const levels = ['none', 'list', 'read', 'write', 'config'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = levels.indexOf(level);
    final need = needs == null ? -1 : levels.indexOf(needs!);
    final fills = [c.line3, c.muted, c.text4, c.ember];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          spacing: 4,
          children: [
            for (var i = 0; i < levels.length; i++)
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= at ? fills[i.clamp(0, 3)] : c.ground4,
                    borderRadius: BorderRadius.circular(4),
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
            for (var i = 0; i < levels.length; i++)
              Expanded(
                child: Text(
                  levels[i],
                  style: mono(
                    size: 12,
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
