import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One icon of the canvas set (`ui/assets/svg/icons/<name>.svg`, 24×24,
/// stroke 1.8, `currentColor`), tinted with [color] or the current
/// `IconTheme`.
///
/// Names by prefix (docs/studio.md §6.4): `ws_` workspaces of the rail,
/// `node_` tree node kinds, `mode_` link run modes, `action_` link actions,
/// `ui_` controls.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {this.size = 20, this.color, super.key});

  /// The file name without `.svg`, e.g. `ws_links`.
  final String name;

  /// 16, 20 or 24.
  final double size;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return SvgPicture.asset(
      'assets/svg/icons/$name.svg',
      package: 'ui',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
