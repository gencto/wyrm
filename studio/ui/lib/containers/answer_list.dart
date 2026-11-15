import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'section_label.dart';

/// One answer of a wizard: what was asked, and what was answered (`—`
/// for none yet).
final class AnswerVm extends Equatable {
  const AnswerVm({required this.label, required this.value});

  final String label;
  final String value;

  @override
  List<Object?> get props => [label, value];
}

/// The right column of a wizard: what was answered so far.
class AnswerList extends StatelessWidget {
  const AnswerList({
    required this.title,
    required this.note,
    required this.answers,
    super.key,
  });

  final String title;
  final String note;

  final List<AnswerVm> answers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        SectionLabel(title),
        Text(
          note,
          style: TextStyle(fontSize: FontSizes.sm, color: c.text3),
        ),
        Gaps.listStart,
        for (final a in answers)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  a.label,
                  style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
                ),
                Text(
                  a.value,
                  style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
