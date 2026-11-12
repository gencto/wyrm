import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// A dialog in the panel style: title, a note, the content, buttons.
class PanelDialog extends StatelessWidget {
  const PanelDialog({
    required this.title,
    required this.child,
    this.note,
    this.actions = const [],
    this.width = 560,
    super.key,
  });

  final String title;
  final String? note;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.ground1,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: AppIcon('ui_close', size: 18, color: c.text3),
                  ),
                ],
              ),
              if (note case final n?)
                Text(n, style: TextStyle(fontSize: 13, color: c.text3)),
              Flexible(child: SingleChildScrollView(child: child)),
              if (actions.isNotEmpty)
                Row(mainAxisAlignment: .end, spacing: 10, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
