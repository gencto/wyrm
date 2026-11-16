import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// An access level (spec 04), as `ui` words it.
enum AccessLevel {
  none,
  list,
  read,
  write,
  config;

  String get label => switch (this) {
    none => S.current.levelNone,
    list => S.current.levelList,
    read => S.current.levelRead,
    write => S.current.levelWrite,
    config => S.current.levelConfig,
  };
}

/// An access level (`read`, `write`, `config`) as a mono chip; `config` is
/// drawn in ember, the level that changes how the network runs.
class LevelBadge extends StatelessWidget {
  /// An [AccessLevel], in its words (`config` stands out).
  LevelBadge.of(AccessLevel level, {super.key})
    : label = level.label,
      strong = level == AccessLevel.config;

  final String label;

  /// `config`: on the ember tint.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: .center,
      decoration: BoxDecoration(
        color: strong ? c.emberTint : c.ground4,
        borderRadius: Radii.chip,
      ),
      child: Text(
        label,
        style: mono(size: 11, color: strong ? c.emberSoft : c.text2),
      ),
    );
  }
}
