import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/sizes.dart';
import 'app_icon.dart';

/// One [AppIcon], tinted with [color] or the current `IconTheme`.
///
/// An icon of the canvas set is [IconSizes.xl] unless [size] says
/// otherwise; a Material glyph without a [size] takes the `IconTheme`'s,
/// as `Icon` does.
class AppIconView extends StatelessWidget {
  const AppIconView(this.icon, {this.size, this.color, super.key});

  final AppIcon icon;

  /// A step of [IconSizes] or a component's own icon size of [AppSizes].
  final double? size;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = icon.asset;
    if (asset == null) {
      return Icon(icon.glyph, size: size, color: color);
    }
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    final side = size ?? IconSizes.xl;
    return SvgPicture.asset(
      'assets/svg/icons/$asset.svg',
      package: 'ui',
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
