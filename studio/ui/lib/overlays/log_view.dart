import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Mono lines in a scrolling, selectable panel (a link's log, a broker log).
class LogView extends StatelessWidget {
  const LogView({
    required this.lines,
    this.loading = false,
    this.empty = '',
    super.key,
  });

  final List<String> lines;
  final bool loading;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground0,
        border: .all(color: c.line1),
        borderRadius: Radii.control,
      ),
      child: loading && lines.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : lines.isEmpty
          ? Center(
              child: Text(
                empty,
                style: TextStyle(fontSize: FontSizes.md, color: c.text4),
              ),
            )
          : Scrollbar(
              child: SelectionArea(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      lines[i],
                      style: mono(
                        size: FontSizes.sm,
                        color: lines[i].contains('ERROR')
                            ? c.badText
                            : (lines[i].contains('WARN') ? c.warn : c.text2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
