import 'package:material_ui/material_ui.dart';

import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// A titled card of a settings-like page: a heading, a sentence that says
/// what the section is, the content, and a foot line that names the key or
/// the action behind it (board `SystemMaint`).
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.description = '',
    this.trailing,
    this.footer = '',
    this.gap = 12,
    this.descriptionWidth,
    super.key,
  });

  final String title;

  /// Code between backticks.
  final String description;

  /// A control at the right of the heading (`Put profile…`).
  final Widget? trailing;
  final Widget child;

  /// Code between backticks.
  final String footer;
  final double gap;

  /// The widest the description gets; the card's width when null.
  final double? descriptionWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: .w600, color: c.text1),
        ),
        if (description.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: descriptionWidth ?? double.infinity,
            ),
            child: CodeText(
              description,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.text3),
            ),
          ),
      ],
    );
    return Semantics(
      container: true,
      label: title,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.ground1,
          border: .all(color: c.line1),
          borderRadius: Radii.panel,
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: gap,
          children: [
            if (trailing case final t?)
              Row(
                crossAxisAlignment: .start,
                spacing: 12,
                children: [
                  Expanded(child: head),
                  t,
                ],
              )
            else
              head,
            child,
            if (footer.isNotEmpty)
              CodeText(
                footer,
                style: TextStyle(fontSize: 12, color: c.text4),
              ),
          ],
        ),
      ),
    );
  }
}
