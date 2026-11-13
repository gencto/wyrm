import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One line of [ViewChecks].
final class ViewCheckVm extends Equatable {
  const ViewCheckVm({required this.tone, required this.text, this.where = ''});

  /// good: passed; warn: drawn with a placeholder; bad: refused.
  final Tone tone;
  final String text;

  /// The component id or the key the line is about, in mono.
  final String where;

  @override
  List<Object?> get props => [tone, text, where];
}

/// The outcome of a view's checks (board `GenViewChecks`): what is wrong
/// first, each line with a mark that differs in shape as well as colour.
class ViewChecks extends StatelessWidget {
  const ViewChecks({required this.checks, super.key});

  final List<ViewCheckVm> checks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (checks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          S.current.viewsNoChecks,
          style: boardText(size: 13, color: c.text4),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: checks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final check = checks[i];
        return Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: StateMark(
                mark: switch (check.tone) {
                  .good => .check,
                  .warn => .ring,
                  _ => .cross,
                },
                color: toneColor(c, check.tone),
                size: 8,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(
                    check.text,
                    style: boardText(size: 13, color: c.text1, height: 1.4),
                  ),
                  if (check.where.isNotEmpty)
                    Text(
                      check.where,
                      style: boardText(size: 12, color: c.text4, code: true),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
