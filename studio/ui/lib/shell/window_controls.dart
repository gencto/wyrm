import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';

/// What [WindowControls] draws.
final class WindowControlsVm extends Equatable {
  const WindowControlsVm({
    this.maximized = false,
    this.minimize = 'Minimize',
    this.maximize = 'Maximize',
    this.restore = 'Restore',
    this.close = 'Close',
  });

  /// The window fills the screen: the middle button restores it.
  final bool maximized;

  /// The buttons' names for assistive technology, localized by the app.
  final String minimize;
  final String maximize;
  final String restore;
  final String close;

  @override
  List<Object?> get props => [maximized, minimize, maximize, restore, close];
}

/// Minimize, maximize or restore, and close of a frameless window on
/// Windows and Linux (owner decision 2026-11-09, docs/studio.md §7.1):
/// three cells of 46 × 32 in the window's top right corner, the icons of
/// the canvas set at 16. The app draws them once, over every page and
/// dialog; a page keeps their [width] free with `WindowBarVm.trailing`.
class WindowControls extends StatelessWidget {
  const WindowControls({
    required this.vm,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
    super.key,
  });

  final WindowControlsVm vm;
  final VoidCallback onMinimize;

  /// Maximizes, or restores when [WindowControlsVm.maximized].
  final VoidCallback onMaximize;
  final VoidCallback onClose;

  static const cellWidth = 46.0;
  static const height = 32.0;

  /// The room the three cells take.
  static const double width = cellWidth * 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: .min,
      children: [
        _Cell(
          icon: 'ui_minimize',
          label: vm.minimize,
          hover: c.ground4,
          onTap: onMinimize,
        ),
        _Cell(
          icon: vm.maximized ? 'ui_restore' : 'ui_maximize',
          label: vm.maximized ? vm.restore : vm.maximize,
          hover: c.ground4,
          onTap: onMaximize,
        ),
        _Cell(
          icon: 'ui_close',
          label: vm.close,
          hover: c.bad,
          hoverInk: c.ground0,
          onTap: onClose,
        ),
      ],
    );
  }
}

/// One button of the three.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.icon,
    required this.label,
    required this.hover,
    required this.onTap,
    this.hoverInk,
  });

  final String icon;
  final String label;
  final Color hover;

  /// The icon's colour over [hover]; null: as at rest.
  final Color? hoverInk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A label and no `Tooltip`: the app draws the cells above its
    // navigator, where there is no overlay for one.
    return Semantics(
      label: label,
      button: true,
      child: Material(
        type: .transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: hover,
          splashFactory: NoSplash.splashFactory,
          canRequestFocus: false,
          child: SizedBox(
            width: WindowControls.cellWidth,
            height: WindowControls.height,
            child: Center(
              child: hoverInk == null
                  ? AppIcon(icon, size: 16, color: c.text2)
                  : _HoverIcon(icon: icon, rest: c.text2, over: hoverInk!),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon that changes colour while the pointer is over its cell.
class _HoverIcon extends StatefulWidget {
  const _HoverIcon({
    required this.icon,
    required this.rest,
    required this.over,
  });

  final String icon;
  final Color rest;
  final Color over;

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<_HoverIcon> {
  var _over = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (_) => setState(() => _over = true),
    onExit: (_) => setState(() => _over = false),
    child: SizedBox.expand(
      child: Center(
        child: AppIcon(
          widget.icon,
          size: 16,
          color: _over ? widget.over : widget.rest,
        ),
      ),
    ),
  );
}
