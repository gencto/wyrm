import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// The app's button, in the four roles of board *Design system* §06.
///
/// Named constructors rather than optional colours, so a caller picks a role
/// and cannot invent a fifth style. One primary per zone: in the top bar it
/// is Review and apply; in a panel it is that panel's commit.
///
/// A button the user's role cannot use is shown disabled with the reason
/// ([disabledReason], docs/studio.md §2 rule 8), never removed.
class Button extends StatelessWidget {
  /// Solid ember fill — the one affirmative action in a zone.
  const Button.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.disabledReason,
    this.size = ButtonSize.toolbar,
    this.fontSize = 14,
    this.fontWeight,
    this.autofocus = false,
    this.inset = 16,
    super.key,
  }) : _variant = .primary;

  /// A line/3 outline — supporting actions.
  const Button.secondary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.disabledReason,
    this.size = ButtonSize.toolbar,
    this.fontSize = 14,
    this.fontWeight,
    this.autofocus = false,
    this.inset = 16,
    super.key,
  }) : _variant = .secondary;

  /// A line/1 outline, quieter text — the third action, a link-like one.
  const Button.quiet({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.disabledReason,
    this.size = ButtonSize.toolbar,
    this.fontSize = 14,
    this.fontWeight,
    this.autofocus = false,
    this.inset = 16,
    super.key,
  }) : _variant = .quiet;

  /// Coral on a bad tint — destructive actions.
  const Button.danger({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.disabledReason,
    this.size = ButtonSize.toolbar,
    this.fontSize = 14,
    this.fontWeight,
    this.autofocus = false,
    this.inset = 16,
    super.key,
  }) : _variant = .danger;

  /// The label; empty for an icon-only button (give it an [icon]).
  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// An icon of `ui/assets/svg/icons` (`ui_add`, `action_play`, …).
  final String? icon;

  /// Stretch to the available width instead of hugging.
  final bool expand;

  /// Why the button is disabled, shown as its tooltip.
  final String? disabledReason;

  final ButtonSize size;

  /// The label's size; 14 everywhere but in a dense toolbar.
  final double fontSize;

  /// The label's weight; the variant's own when null (600 primary, 500
  /// the others).
  final FontWeight? fontWeight;

  /// Takes the focus when it is first built: the main button of a dialog,
  /// so Enter presses it.
  final bool autofocus;

  /// The room left and right of the label; 16 everywhere but where a
  /// board draws another.
  final double inset;

  final _Variant _variant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final (background, foreground, border) = switch (_variant) {
      .primary => (c.ember, c.onEmber, c.ember),
      .secondary => (Colors.transparent, c.text1, c.line3),
      .quiet => (Colors.transparent, c.text2, c.line1),
      .danger => (c.badTint, c.badText, c.badLine),
    };
    final height = size.height;
    final iconOnly = label.isEmpty && icon != null;
    final fg = enabled ? foreground : c.muted;
    final child = Row(
      mainAxisSize: expand ? .max : .min,
      mainAxisAlignment: .center,
      spacing: 8,
      children: [
        if (icon case final name?) AppIcon(name, size: 16, color: fg),
        if (label.isNotEmpty)
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: fontSize,
              fontWeight: fontWeight ?? (_variant == .primary ? .w600 : .w500),
              color: fg,
            ),
          ),
      ],
    );
    final button = Material(
      color: enabled
          ? background
          : (_variant == .primary ? c.ground4 : Colors.transparent),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.button,
        side: BorderSide(color: enabled ? border : c.line1),
      ),
      child: InkWell(
        onTap: onPressed,
        autofocus: autofocus,
        borderRadius: Radii.button,
        hoverColor: c.text1.withValues(alpha: 0.05),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: iconOnly ? height : 0,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : inset),
            child: Center(widthFactor: expand ? null : 1, child: child),
          ),
        ),
      ),
    );
    final sized = expand ? SizedBox(width: .infinity, child: button) : button;
    final reason = disabledReason;
    if (!enabled && reason != null) {
      return Tooltip(message: reason, child: sized);
    }
    if (iconOnly && label.isEmpty) {
      return Semantics(button: true, child: sized);
    }
    return sized;
  }
}

/// Board *Design system* §04 heights.
enum ButtonSize {
  /// An inline control, 32.
  small(32),

  /// A toolbar button, 40.
  /// A toolbar inside a card (36 px): the Log toolbar, a card's own
  /// button.
  compact(36),

  toolbar(40),

  /// A commit button, 44.
  commit(44);

  const ButtonSize(this.height);

  final double height;
}

enum _Variant { primary, secondary, quiet, danger }
