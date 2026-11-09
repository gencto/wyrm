import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// An access level (`read`, `write`, `config`) as a mono chip; `config` is
/// drawn in ember, the level that changes how the network runs.
class LevelBadge extends StatelessWidget {
  const LevelBadge({required this.level, super.key});

  final String level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final config = level == 'config';
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: .center,
      decoration: BoxDecoration(
        color: config ? c.emberTint : c.ground4,
        borderRadius: Radii.chip,
      ),
      child: Text(
        level,
        style: mono(size: 11, color: config ? c.emberSoft : c.text2),
      ),
    );
  }
}
