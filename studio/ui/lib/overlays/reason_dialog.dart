import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// Asks for a reason before something is refused (Reject of a plan): a
/// message, one text field, and the two buttons. The reason may stay empty.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({
    required this.title,
    required this.message,
    required this.hint,
    required this.confirm,
    required this.cancel,
    super.key,
  });

  final String title;
  final String message;
  final String hint;
  final String confirm;
  final String cancel;

  /// Shows it; the reason as typed (may be empty), or null when cancelled.
  static Future<String?> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String hint,
    required String confirm,
    required String cancel,
  }) => showDialog<String>(
    context: context,
    builder: (_) => ReasonDialog(
      title: title,
      message: message,
      hint: hint,
      confirm: confirm,
      cancel: cancel,
    ),
  );

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_text.text.trim());

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
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                widget.message,
                style: TextStyle(fontSize: 14, color: c.text2),
              ),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _done(),
                style: TextStyle(fontSize: 14, color: c.text1),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: .end,
                spacing: 10,
                children: [
                  Button.quiet(
                    label: widget.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Button.danger(label: widget.confirm, onPressed: _done),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
