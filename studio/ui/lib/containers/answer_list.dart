import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import 'section_label.dart';

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

  /// Label and answer pairs; `—` for none yet.
  final List<(String, String)> answers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        SectionLabel(title),
        Text(note, style: TextStyle(fontSize: 12, color: c.text3)),
        const SizedBox(height: 10),
        for (final (label, value) in answers)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: c.text4)),
                Text(value, style: TextStyle(fontSize: 14, color: c.text1)),
              ],
            ),
          ),
      ],
    );
  }
}
