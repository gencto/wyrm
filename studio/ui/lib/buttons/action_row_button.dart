import 'package:flutter/material.dart';

import 'button.dart';

// TODO(frx): describe what this action does.
class ActionRowButton extends StatelessWidget {
  const ActionRowButton({
    required this.onPressed,
    this.expand = false,
    super.key,
  });

  /// Null disables the button; the theme dims it.
  final VoidCallback? onPressed;

  /// Stretch to the available width instead of hugging.
  final bool expand;

  @override
  Widget build(BuildContext context) => Button.primary(
    // TODO(frx): the label belongs in localization — S.current.
    label: 'ActionRow',
    onPressed: onPressed,
    expand: expand,
  );
}
