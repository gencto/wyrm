import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// Asks before something that cannot be undone; the confirm button is the
/// danger one when [danger].
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirm,
    required this.cancel,
    this.danger = true,
    super.key,
  });

  final String title;
  final String message;
  final String confirm;
  final String cancel;
  final bool danger;

  /// Shows it; true when confirmed.
  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String confirm,
    required String cancel,
    bool danger = true,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => ConfirmDialog(
          title: title,
          message: message,
          confirm: confirm,
          cancel: cancel,
          danger: danger,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.ground1,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(message, style: TextStyle(fontSize: 14, color: c.text2)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: .end,
                spacing: 10,
                children: [
                  Button.quiet(
                    label: cancel,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  if (danger)
                    Button.danger(
                      label: confirm,
                      onPressed: () => Navigator.of(context).pop(true),
                    )
                  else
                    Button.primary(
                      label: confirm,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
